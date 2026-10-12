# itera's declarative-Flatpak battery.
#
# A thin wrapper over nix-flatpak (bundled by `modules/nixos/default.nix`), which
# adds declarative `services.flatpak.packages` / `services.flatpak.remotes` on top
# of NixOS's native `services.flatpak`. Useful for GUI apps that are awkward to
# package in nixpkgs or that you want to run in Flatpak's sandbox on the
# mango/DankMaterialShell desktop.
#
# Opt-IN (default OFF): unlike most itera batteries this defaults off, because it
# adds the networked Flathub remote — a deliberate expansion of trust/attack
# surface against itera's hardened base, so you turn it on explicitly. When on,
# `itera.impermanence` persists `/var/lib/flatpak` so installed apps survive the
# ephemeral root.
{
  config,
  options,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.flatpak;
in
{
  options.itera.desktop.flatpak = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable declarative Flatpak management (nix-flatpak). OFF by default (it
        adds the Flathub remote); set to `true` to opt in. Declared packages are
        installed and the Flathub remote is configured automatically.
      '';
    };

    packages = mkOption {
      # nix-flatpak's own type, so a misspelled key fails at eval time.
      inherit (options.services.flatpak.packages) type;
      default = [ ];
      example = [
        "com.brave.Browser"
        {
          appId = "org.gimp.GIMP";
          origin = "flathub";
        }
      ];
      description = ''
        Flatpak apps to install declaratively, passed through to
        {option}`services.flatpak.packages`. Each entry is an application id
        (installed from Flathub) or an attrset with {option}`appId`/{option}`origin`.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.flatpak = {
      enable = mkDefault true;
      # adw-gtk3 for GTK3 apps in both modes (docs/look.md#flatpaks).
      packages = cfg.packages ++ [
        "org.gtk.Gtk3theme.adw-gtk3"
        "org.gtk.Gtk3theme.adw-gtk3-dark"
      ];
      # The look's one Flatpak override, with no colours: Flatpaks read DMS's
      # gtk.css and the host cursors. No /nix/store grant, so any look file a
      # Flatpak reads must be a real file, not a hjem store symlink.
      overrides.settings.global = {
        Context.filesystems = [
          "xdg-config/gtk-3.0:ro"
          "xdg-config/gtk-4.0:ro"
        ];
        Environment.XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
      };
    };
  };
}
