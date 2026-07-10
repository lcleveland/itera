# Evaluation check for itera's ecosystem-integration batteries: agenix secrets,
# nix-index/comma, QEMU/KVM virtualization, the Nemo file manager, Secure Boot
# (lanzaboote), declarative Flatpak, and nixos-facter.
#
# Like tests/eval.nix, these are hard to VM-boot (Secure Boot needs enrolled keys,
# libvirt/flatpak pull services) so we evaluate two NixOS configurations — one at
# defaults, one with the opt-in batteries turned on — and assert the generated
# config. `nix build` forces evaluation and fails loudly on any false assertion.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  mkEval =
    extra:
    (nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.default
        {
          system.stateVersion = "25.05";
          itera = {
            enable = true;
            disko = {
              enable = true;
              device = "/dev/vda";
            };
            impermanence.enable = true;
          };
        }
        extra
      ];
    }).config;

  # Defaults: opt-out batteries on, opt-in batteries off.
  base = mkEval { };

  # Opt-in batteries turned on (Secure Boot + Flatpak).
  optIn = mkEval {
    itera.secureBoot.enable = true;
    itera.desktop.flatpak.enable = true;
  };

  persistDirs = cfg: map (d: d.directory or d) cfg.environment.persistence."/persist".directories;

  checks = {
    # --- agenix (default on, inert) ---
    "agenix identity is the persisted host key" =
      builtins.elem "/etc/ssh/ssh_host_ed25519_key" base.age.identityPaths;

    # --- nix-index + comma (default on) ---
    "nix-index is enabled" = base.programs.nix-index.enable;
    "comma is enabled" = base.programs.nix-index-database.comma.enable;

    # --- virtualisation (default on) ---
    "libvirtd is enabled" = base.virtualisation.libvirtd.enable;
    "virt-manager GUI is enabled" = base.programs.virt-manager.enable;
    "swtpm is enabled for guests" = base.virtualisation.libvirtd.qemu.swtpm.enable;
    "libvirt state is persisted" = builtins.elem "/var/lib/libvirt" (persistDirs base);

    # --- Nemo file manager (default on) ---
    "gvfs is enabled" = base.services.gvfs.enable;
    "tumbler thumbnails are enabled" = base.services.tumbler.enable;
    "nemo is the default directory handler" =
      base.xdg.mime.defaultApplications."inode/directory" == "nemo.desktop";

    # --- dark mode by default ---
    "GTK apps default to dark" = base.environment.sessionVariables.GTK_THEME == "Adwaita:dark";
    "DMS shell defaults to dark (portal sync off)" =
      base.itera.desktop.dankMaterialShell.settings.syncModeWithPortal == false;

    # --- Secure Boot (default OFF, so systemd-boot stays) ---
    "lanzaboote is off by default" = !base.boot.lanzaboote.enable;
    "systemd-boot is on by default" = base.boot.loader.systemd-boot.enable;

    # --- Flatpak (default OFF) ---
    "flatpak is off by default" = !base.services.flatpak.enable;

    # --- facter (default: no report) ---
    "facter reportPath is null by default" = base.facter.reportPath == null;

    # --- Secure Boot opt-in: swaps bootloader + persists keys ---
    "lanzaboote turns on when opted in" = optIn.boot.lanzaboote.enable;
    "systemd-boot is forced off under Secure Boot" = !optIn.boot.loader.systemd-boot.enable;
    "Secure Boot keys are persisted when opted in" = builtins.elem "/var/lib/sbctl" (persistDirs optIn);

    # --- Flatpak opt-in: enables service + persists installs ---
    "flatpak turns on when opted in" = optIn.services.flatpak.enable;
    "flatpak state is persisted when opted in" = builtins.elem "/var/lib/flatpak" (persistDirs optIn);
  };

  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
pkgs.runCommand "itera-integrations-eval" { } (
  if failed == [ ] then
    "touch $out"
  else
    throw "itera integrations eval check failed: ${lib.concatStringsSep "; " failed}"
)
