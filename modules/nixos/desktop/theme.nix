# itera's appearance / color-scheme battery.
#
# itera's desktop defaults to DARK. The Quickshell shell (DankMaterialShell)
# already renders dark by itself (see `itera.desktop.dankMaterialShell`, which
# pins `syncModeWithPortal = false` so DMS uses its dark `isLightMode = false`
# default). This battery extends the same dark default to the GTK apps itera
# ships — Nemo (`itera.desktop.fileManager`), virt-manager
# (`itera.virtualisation`), file-roller — and to any GTK/Flatpak app that follows
# the freedesktop color-scheme preference:
#
#   - GTK_THEME=Adwaita:dark forces GTK2/3 apps to the dark Adwaita variant
#     (built into GTK — no extra theme package needed).
#   - the dconf `color-scheme = prefer-dark` is the signal libadwaita/GTK4 apps
#     and the xdg-desktop-portal settings interface (hence Flatpak apps) read to
#     pick their dark palette.
#
# Opt-out like the other desktop batteries: gated on the master `itera.enable`
# with `mkDefault` values. Flip `itera.desktop.theme.dark = false` for a light
# session, or `itera.desktop.theme.enable = false` to manage GTK theming yourself.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.theme;
in
{
  options.itera.desktop.theme = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Apply itera's system-wide GTK color-scheme preference so bundled GTK apps
        (Nemo, virt-manager, …) match the desktop. On by default whenever
        {option}`itera.enable` is set.
      '';
    };

    dark = mkOption {
      type = bool;
      default = true;
      description = ''
        Prefer a dark color scheme for GTK/Flatpak apps (matching DankMaterialShell's
        own dark default). Set to `false` for a light session.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    # GTK2/3 apps: force the Adwaita dark/light variant directly.
    environment.sessionVariables.GTK_THEME = mkDefault (if cfg.dark then "Adwaita:dark" else "Adwaita");

    # libadwaita/GTK4 apps + the settings portal (Flatpak) follow this preference.
    programs.dconf.enable = mkDefault true;
    programs.dconf.profiles.user.databases = [
      {
        settings."org/gnome/desktop/interface".color-scheme = if cfg.dark then "prefer-dark" else "default";
      }
    ];
  };
}
