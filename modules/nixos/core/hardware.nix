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
# boots virtually every modern UEFI x86 machine (NVMe, SATA, virtio, thunderbolt,
# SD/MMC). "available" modules are only pulled into the initrd and probed — the
# ones whose hardware is absent cost a little initrd size and nothing else — so
# the list is set additively (no `mkDefault`) and coexists with modules
# contributed by the qemu-guest profile or the NixOS test driver. USB controllers
# are the exception: they're opt-in via `initrd.usbSupport` (off by default),
# since enumerating USB in stage 1 lets a faulty USB device stall switch-root.
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
  inherit (lib.modules) mkIf mkDefault mkForce;
  inherit (lib.types)
    bool
    enum
    listOf
    str
    package
    ;

  inherit (lib.lists) optionals;

  cfg = config.itera.hardware;

  # Disk/storage controllers the initrd needs to find and mount root. Always
  # included — root lives on one of these on every supported machine.
  diskInitrdModules = [
    "nvme"
    "nvme_core"
    "ahci"
    "ata_piix"
    "sd_mod"
    "sr_mod"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "thunderbolt"
    "sdhci_pci"
    "mmc_block"
  ];

  # USB host-controller + HID modules. Only needed in the initrd to type a LUKS
  # passphrase on a USB keyboard or to boot from a USB device — see
  # `initrd.usbSupport`. Gated because enumerating USB in stage 1 lets a
  # slow/faulty USB device stall switch-root for ~60s.
  usbInitrdModules = [
    "xhci_pci"
    "ehci_pci"
    "ohci_pci"
    "uhci_hcd"
    "usb_storage"
    "usbhid"
  ];

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
      usbSupport = mkOption {
        type = bool;
        default = false;
        description = ''
          Include USB host-controller and HID modules in the initrd. Opt-in,
          because bringing USB up in stage 1 lets a slow or faulty USB device
          stall switch-root: a broken device retrying enumeration in the initrd
          can block the *entire* boot for ~60s before the real root is even
          activated. With this off, USB comes up in stage 2 instead, off the
          critical path to login.

          Enable it only when early boot genuinely needs USB — to type a LUKS
          passphrase on a USB keyboard, or to boot from a USB device. A default
          NVMe/SATA root with no LUKS does not.

          When off, this also suppresses nixos-facter's USB-controller injection
          into the initrd (see {file}`facter.nix`), so the opt-out holds even on
          a facter-managed host.
        '';
      };

      availableKernelModules = mkOption {
        type = listOf str;
        default = diskInitrdModules ++ optionals cfg.initrd.usbSupport usbInitrdModules;
        defaultText = lib.literalMD ''
          A broad curated set of disk controllers (NVMe, SATA, virtio,
          thunderbolt, SD/MMC), plus USB host-controller + HID modules only when
          {option}`itera.hardware.initrd.usbSupport` is enabled (off by default).
        '';
        description = ''
          Modules made available to the initrd so it can find and mount the root
          device. The default is a broad set covering common disk controllers
          (and USB controllers only when {option}`itera.hardware.initrd.usbSupport`
          is enabled); add entries here for an exotic controller the default
          misses. These are concatenated with modules from other sources (e.g.
          the qemu-guest profile), not overridden.
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
      initrd = {
        # List options; set plainly so they concatenate with any modules the
        # qemu-guest profile or NixOS test driver also contribute.
        availableKernelModules = cfg.initrd.availableKernelModules;
        kernelModules = cfg.initrd.kernelModules;

        # nixpkgs' `includeDefaultModules` (default true) unconditionally adds a
        # kitchen-sink set to the initrd — legacy SATA/PATA *and* the whole USB
        # keyboard stack (xhci/ehci/ohci/uhci + usbhid + hid_*). That, not
        # itera's own list, is the main reason USB gets enumerated in stage 1.
        # When USB in the initrd is opted out, drop it: itera's curated
        # `availableKernelModules` plus facter's detected disk controllers
        # already cover what boots the machine. mkDefault so a host that needs a
        # default-set module back (e.g. `dm_mod` for LVM, a legacy SATA chipset)
        # can re-enable it or add the module explicitly.
        includeDefaultModules = mkIf (!cfg.initrd.usbSupport) (mkDefault false);
      };
      kernelModules = kvmModules ++ cfg.kernelModules;
      inherit (cfg) extraModulePackages;
    };

    # When USB in the initrd is opted out, also neutralise nixos-facter, which
    # otherwise re-adds every USB controller to the initrd via its keyboard
    # detection (`keyboard.kernelModules` defaults to the drivers of every
    # `report.hardware.usb_controller`, for the USB-keyboard-at-LUKS case). Left
    # alone, that would silently undo `usbSupport = false` on any facter host.
    # Overriding the detected option to `[]` is a no-op when no report is wired
    # (its default is already empty) and harmless when usbSupport is on.
    facter.detected.boot.keyboard.kernelModules = mkIf (!cfg.initrd.usbSupport) (mkForce [ ]);

    hardware = {
      enableRedistributableFirmware = mkDefault cfg.redistributableFirmware;
      cpu.intel.updateMicrocode = mkDefault (cfg.cpu == "intel" || cfg.cpu == "auto");
      cpu.amd.updateMicrocode = mkDefault (cfg.cpu == "amd" || cfg.cpu == "auto");
    };

    # Compressed in-RAM swap. itera's disko layouts ship no swap partition, so
    # without this the kernel has no swap at all — systemd-oomd degrades its
    # memory-pressure handling and logs "No swap; memory pressure usage will be
    # degraded" every boot. zram gives a swap device that lives in RAM, so it
    # both silences that and improves behaviour under pressure. Opt-out via
    # mkDefault, matching the rest of itera's battery shape.
    zramSwap.enable = mkDefault true;
  };
}
