# itera's GTK battery (docs/look.md#light-dark-and-auto).
#
# DankMaterialShell owns the live light/dark mode, seeded per user from
# `look.mode` (modules/hjem/look-seed.nix), and themes GTK itself: it writes
# `dank-colors.css` and picks the adw-gtk3 variant for the mode. This battery
# supplies what that needs system-wide, for the GTK apps itera ships (Nemo,
# virt-manager, file-roller) and any GTK/Flatpak app:
#
#   - adw-gtk3, the GTK3 theme DMS colours.
#   - the system dconf `color-scheme`, from the system look: a floor under every
#     user, for users itera doesn't manage and the moment before the seeder runs.
#     Auto starts dark.
#
# GTK_THEME is never set: it would pin GTK3 apps past DMS's theme and mode, so an
# assertion keeps it out while DMS is on.
#
# Opt-out like the other desktop batteries: gated on the master `itera.enable`.
# Set `itera.desktop.theme.enable = false` to manage GTK theming yourself.
{
  config,
  lib,
  pkgs,
  iteraLib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.theme;
in
{
  imports = [
    # Dropped at NixOS 26.11.
    (lib.mkChangedOptionModule [ "itera" "desktop" "theme" "dark" ] [ "itera" "look" "mode" ] (
      config: if config.itera.desktop.theme.dark then "dark" else "light"
    ))
  ];

  options.itera.desktop.theme.enable = mkOption {
    type = bool;
    default = true;
    description = ''
      Ship adw-gtk3 and set the system-wide dconf color-scheme from the system
      look, so GTK apps (Nemo, virt-manager, …) match the desktop. On by default
      whenever {option}`itera.enable` is set.
    '';
  };

  config = mkIf config.itera.enable (mkMerge [
    (mkIf cfg.enable {
      environment.systemPackages = [ pkgs.adw-gtk3 ];

      # libadwaita/GTK4 apps + the settings portal (Flatpak) follow this preference.
      programs.dconf.enable = mkDefault true;
      programs.dconf.profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface".color-scheme =
            if (iteraLib.look.resolve config null).startMode == "light" then "default" else "prefer-dark";
        }
      ];
    })

    {
      assertions = [
        {
          assertion =
            !(config.itera.desktop.dankMaterialShell.enable && config.environment.sessionVariables ? GTK_THEME);
          message = "itera: GTK_THEME pins GTK apps past DankMaterialShell's theme and mode; leave it unset while DMS is on (docs/look.md#delivery-lanes).";
        }
      ];
    }
  ]);
}
