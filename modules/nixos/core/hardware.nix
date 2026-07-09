# itera's hardware battery: initrd kernel modules, CPU microcode, firmware.
#
# This is the piece that lets a host boot with NO generated
# `hardware-configuration.nix`. Everything a `nixos-generate-config` file used to
# contribute — the disk/USB controller modules the initrd needs to find and mount
# root, the `kvm-*` module, CPU microcode, and redistributable firmware — is
# supplied here declaratively. Combined with `itera.disko` (filesystems/swap),
# `itera.boot` (bootloader), and `itera.nix` (`system.stateVersion`), a host is
# described entirely through `itera.*`.
#
# The `availableKernelModules` default is a deliberately broad *curated* set that
# boots virtually every modern UEFI x86 machine (NVMe, SATA, all USB gens,
# virtio, thunderbolt, SD/MMC). "available" modules are only pulled into the
# initrd and probed — the ones whose hardware is absent cost a little initrd size
# and nothing else — so the list is set additively (no `mkDefault`) and coexists
# with modules contributed by the qemu-guest profile or the NixOS test driver.
#
# Opt-OUT with its own `enable` (like `itera.disko`/`itera.impermanence`): on by
# default with `itera.enable`, but a clean off-switch for the advanced path where
# you bring your own `hardware-configuration.nix` (e.g. a pre-partitioned machine
# that also sets `itera.disko.enable = false`).
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    bool
    enum
    listOf
    str
    package
    ;

  cfg = config.itera.hardware;

  # `kvm-*` for the selected vendor. "auto" loads neither (the module is only
  # needed for virtualization, not to boot); pick a vendor to get it.
  kvmModules =
    {
      intel = [ "kvm-intel" ];
      amd = [ "kvm-amd" ];
      auto = [ ];
    }
    .${cfg.cpu};
in
{
  options.itera.hardware = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Whether to supply itera's hardware layer (initrd kernel modules, CPU
        microcode, redistributable firmware). On by default whenever
        {option}`itera.enable` is set. Set to `false` to manage these yourself —
        e.g. when providing your own generated {file}`hardware-configuration.nix`.
      '';
    };

    cpu = mkOption {
      type = enum [
        "intel"
        "amd"
        "auto"
      ];
      default = "auto";
      description = ''
        CPU vendor. Selects the microcode updates and the `kvm-*` module.
        `"auto"` (the default) enables *both* Intel and AMD microcode — harmless
        on the non-matching vendor — for a hardware-agnostic image, and loads no
        `kvm-*` module. Set `"intel"` or `"amd"` to also load `kvm-intel`/`kvm-amd`.
      '';
    };

    redistributableFirmware = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable {option}`hardware.enableRedistributableFirmware` so drivers that
        need unfree firmware blobs (Wi-Fi, GPUs, …) work out of the box.
      '';
    };

    initrd = {
      availableKernelModules = mkOption {
        type = listOf str;
        default = [
          "nvme"
          "nvme_core"
          "ahci"
          "ata_piix"
          "sd_mod"
          "sr_mod"
          "xhci_pci"
          "ehci_pci"
          "ohci_pci"
          "uhci_hcd"
          "usb_storage"
          "usbhid"
          "virtio_pci"
          "virtio_blk"
          "virtio_scsi"
          "virtio_net"
          "thunderbolt"
          "sdhci_pci"
          "mmc_block"
        ];
        description = ''
          Modules made available to the initrd so it can find and mount the root
          device. The default is a broad set covering common disk/USB controllers;
          add entries here for an exotic controller the default misses. These are
          concatenated with modules from other sources (e.g. the qemu-guest
          profile), not overridden.
        '';
      };

      kernelModules = mkOption {
        type = listOf str;
        default = [ ];
        example = [ "virtio_gpu" ];
        description = "Modules force-loaded in the initrd (stage 1).";
      };
    };

    kernelModules = mkOption {
      type = listOf str;
      default = [ ];
      description = ''
        Extra kernel modules to load in stage 2, in addition to the `kvm-*`
        module selected by {option}`itera.hardware.cpu`.
      '';
    };

    extraModulePackages = mkOption {
      type = listOf package;
      default = [ ];
      description = "Out-of-tree kernel module packages to make available.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    boot = {
      # List options; set plainly so they concatenate with any modules the
      # qemu-guest profile or NixOS test driver also contribute.
      initrd.availableKernelModules = cfg.initrd.availableKernelModules;
      initrd.kernelModules = cfg.initrd.kernelModules;
      kernelModules = kvmModules ++ cfg.kernelModules;
      inherit (cfg) extraModulePackages;
    };

    hardware = {
      enableRedistributableFirmware = mkDefault cfg.redistributableFirmware;
      cpu.intel.updateMicrocode = mkDefault (cfg.cpu == "intel" || cfg.cpu == "auto");
      cpu.amd.updateMicrocode = mkDefault (cfg.cpu == "amd" || cfg.cpu == "auto");
    };
  };
}
