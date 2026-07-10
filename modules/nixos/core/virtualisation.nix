# itera's virtualization battery: QEMU/KVM via libvirt + the virt-manager GUI.
#
# Native NixOS feature (no flake input) wiring `virtualisation.libvirtd` and
# `programs.virt-manager` into an opinionated, ready-to-use setup: KVM-accelerated
# QEMU with OVMF (UEFI guests) and swtpm (emulated TPM) — matching itera's own
# Secure-Boot/TPM-forward posture — plus virt-manager as the graphical manager for
# the mango/DankMaterialShell desktop.
#
# Opt-OUT (default ON). Two things to know:
#   - KVM acceleration needs the `kvm-*` module, which `itera.hardware` only loads
#     when `itera.hardware.cpu` is "intel"/"amd" (not the "auto" default). This
#     module warns if virtualization is on while cpu is "auto".
#   - libvirt access is granted to every `itera.users` account via the libvirtd
#     group (below). Users declared the plain NixOS way should add "libvirtd" to
#     their own `extraGroups`.
#
# Under impermanence, `/var/lib/libvirt` (domains, storage pools, nvram) is added
# to the persisted set by `itera.impermanence` while this battery is enabled.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.virtualisation;
in
{
  options.itera.virtualisation = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable QEMU/KVM virtualization via libvirt. On by default whenever
        {option}`itera.enable` is set; set to `false` to opt out.
      '';
    };

    gui.enable = mkOption {
      type = bool;
      default = true;
      description = "Install virt-manager, the graphical VM manager.";
    };

    spiceUSBRedirection.enable = mkOption {
      type = bool;
      default = true;
      description = "Enable SPICE USB redirection so guests can use host USB devices.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    warnings = lib.optional (config.itera.hardware.enable && config.itera.hardware.cpu == "auto") ''
      itera.virtualisation is enabled but itera.hardware.cpu = "auto", so no kvm-*
      module is loaded and VMs will run without KVM acceleration. Set
      itera.hardware.cpu = "intel" or "amd" for hardware acceleration.
    '';

    virtualisation.libvirtd = {
      enable = mkDefault true;
      qemu = {
        package = mkDefault pkgs.qemu_kvm;
        # OVMF (UEFI firmware for guests) ships with QEMU by default now; swtpm
        # gives guests an emulated TPM 2.0, matching itera's TPM-forward posture.
        swtpm.enable = mkDefault true;
      };
    };

    programs.virt-manager.enable = mkDefault cfg.gui.enable;
    virtualisation.spiceUSBRedirection.enable = mkDefault cfg.spiceUSBRedirection.enable;

    # Grant every itera-declared user libvirt access. Done via the group's
    # `members` (not users.users.*.extraGroups) so it does not collide with the
    # mkDefault extraGroups list that core/users.nix sets.
    users.groups.libvirtd.members = lib.attrNames config.itera.users;
  };
}
