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
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;

  # This check exercises impermanence persistence, so turn disko + impermanence
  # on (overriding mkConfig's defaults) alongside each variant's extra module.
  diskoOn = {
    itera.disko = {
      enable = true;
      device = "/dev/vda";
    };
    itera.impermanence.enable = true;
  };
  mkEval =
    extra:
    mkConfig [
      diskoOn
      extra
    ];

  # Defaults: opt-out batteries on, opt-in batteries off.
  base = mkEval { };

  # Opt-in batteries turned on (Secure Boot + Flatpak).
  optIn = mkEval {
    itera.secureBoot.enable = true;
    itera.desktop.flatpak.enable = true;
  };

  # Default-on batteries turned OFF, to assert their persisted state is gated:
  # Bluetooth (system dir) and the LibreWolf profile (per-user home dir).
  batteriesOff = mkEval {
    itera = {
      users.testuser = { };
      bluetooth.enable = false;
      desktop.browser.enable = false;
    };
  };
  # Same account with the batteries left on, to assert the profile IS persisted.
  batteriesOn = mkEval { itera.users.testuser = { }; };

  persistDirs = cfg: map (d: d.directory or d) cfg.environment.persistence."/persist".directories;
  userDirs =
    cfg: name:
    map (d: d.directory or d) cfg.environment.persistence."/persist".users.${name}.directories;

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

    # --- LibreWolf browser (default on) ---
    "librewolf is the default https handler" =
      base.xdg.mime.defaultApplications."x-scheme-handler/https" == "librewolf.desktop";
    "browser keybind command is wired" = base.itera.desktop.mango.commands.browser == "librewolf";
    # The ~/.librewolf profile is persisted while the battery is on, and gated off
    # with it (it lives outside the curated home dirs, so it must be added/removed
    # with the browser rather than persisted unconditionally).
    "librewolf profile persisted when browser on" = builtins.elem ".librewolf" (
      userDirs batteriesOn "testuser"
    );
    "librewolf profile not persisted when browser off" =
      !builtins.elem ".librewolf" (userDirs batteriesOff "testuser");

    # --- Bluetooth (default on): pairings persisted, gated on the battery ---
    "bluetooth pairings persisted when on" = builtins.elem "/var/lib/bluetooth" (persistDirs base);
    "bluetooth pairings not persisted when off" =
      !builtins.elem "/var/lib/bluetooth" (persistDirs batteriesOff);

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

in
mkCheckDrv "itera-integrations-eval" checks
