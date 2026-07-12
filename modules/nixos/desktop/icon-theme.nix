# itera's icon-theme battery.
#
# The Wayland desktop is Quickshell/Qt-based (DankMaterialShell). Quickshell
# resolves system-tray (SNI) icon *names* — udiskie's removable-drive glyph,
# DMS's own menu icons — through the Qt icon theme. itera otherwise installs no
# icon theme, so those names fail to resolve and render as a magenta "missing
# icon" placeholder. This battery ships a complete theme and names it for the
# shell (QS_ICON_THEME, honoured by Quickshell) so icons resolve.
#
# Opt-out like the other batteries: gated on the master `itera.enable` with
# `mkDefault` values, so it is on by default yet fully overridable.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkPackageOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool str;

  cfg = config.itera.desktop.iconTheme;
in
{
  options.itera.desktop.iconTheme = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install a system icon theme so desktop/tray (SNI) icons resolve.";
    };

    package = mkPackageOption pkgs "adwaita-icon-theme" { };

    name = mkOption {
      type = str;
      default = "Adwaita";
      description = ''
        Icon theme name Quickshell/DMS should use (`QS_ICON_THEME`). Must match a
        theme provided by {option}`itera.desktop.iconTheme.package`.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ cfg.package ];
    environment.sessionVariables.QS_ICON_THEME = cfg.name;
  };
}
