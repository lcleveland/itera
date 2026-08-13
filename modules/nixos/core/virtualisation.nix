# itera's virtualization battery: QEMU/KVM via libvirt + the virt-manager GUI.
#
# Native NixOS feature (no flake input) wiring `virtualisation.libvirtd` and
# `programs.virt-manager` into an opinionated, ready-to-use setup: KVM-accelerated
# QEMU with OVMF (UEFI guests) and swtpm (emulated TPM) — matching itera's own
# Secure-Boot/TPM-forward posture — plus virt-manager as the graphical manager for
# the mango/DankMaterialShell desktop, and libvirt's `default` NAT network started
# and set to autostart (upstream defines it but leaves it down).
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

    defaultNetwork.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Start libvirt's built-in `default` NAT network (the `virbr0` bridge every
        new virt-manager VM is wired to) and mark it autostart, so guests boot
        without "network 'default' is not active". Set to `false` if you manage
        guest networking yourself (a host bridge, macvtap, …) and don't want the
        NAT bridge and its dnsmasq running.
      '';
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

    # libvirt's `default` NAT network: DEFINED out of the box but never STARTED.
    # nixpkgs' libvirtd-config copies the package's network XMLs into
    # /var/lib/libvirt/qemu/networks, but not the `autostart/` symlink that lives
    # beside them, so libvirtd comes up with the network known and inactive — and
    # every VM that references it dies with "Requested operation is not valid:
    # network 'default' is not active". Start it and flag it autostart here.
    #
    # Done as a unit rather than a tmpfiles autostart symlink so it also takes
    # effect on `nixos-rebuild switch`, not just at the next boot. Idempotent:
    # re-running it on a host where the network is already up is a no-op.
    # Gated on libvirtd actually being on: itera sets it with mkDefault, so a
    # consumer can still turn the daemon off, and a unit requiring a libvirtd.service
    # that does not exist would just fail at boot.
    systemd.services.itera-libvirt-default-network =
      mkIf (cfg.defaultNetwork.enable && config.virtualisation.libvirtd.enable)
        {
          description = "Start libvirt's default NAT network";
          wantedBy = [ "multi-user.target" ];
          after = [ "libvirtd.service" ];
          requires = [ "libvirtd.service" ];
          path = [ pkgs.gnugrep ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "itera-libvirt-default-network" ''
              set -euo pipefail

              virsh() { ${lib.getExe' config.virtualisation.libvirtd.package "virsh"} --connect qemu:///system "$@"; }

              # Define it if it is missing entirely (a host whose /var/lib/libvirt
              # predates the XML, or where it was undefined by hand).
              if ! virsh net-info default >/dev/null 2>&1; then
                virsh net-define ${config.virtualisation.libvirtd.package}/var/lib/libvirt/qemu/networks/default.xml
              fi

              virsh net-autostart default
              # `net-list --name` lists the ACTIVE networks, so this both skips the
              # start when it is already up (net-start would fail) and does it again
              # after a manual `net-destroy`.
              if ! virsh net-list --name | grep -qx default; then
                virsh net-start default
              fi
            '';
          };
        };

    # Grant every itera-declared user libvirt access. Done via the group's
    # `members` (not users.users.*.extraGroups) so it does not collide with the
    # mkDefault extraGroups list that core/users.nix sets.
    users.groups.libvirtd.members = lib.attrNames config.itera.users;
  };
}
