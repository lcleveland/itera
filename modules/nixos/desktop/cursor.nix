# itera's cursor battery.
#
# Installs the look's cursor theme (Bibata Modern Ice dark, Classic light, 24 by
# default) and sends the starting mode's theme and size everywhere a cursor is
# read: `XCURSOR_*` and dconf `cursor-theme`/`cursor-size` (the system look as the
# floor, each user's own over it), and per user DMS `cursorSettings` (and so
# mango, which exports `XCURSOR_*` from it), `~/.config/environment.d` and
# `~/.Xresources` (modules/hjem/programs/dankmaterialshell.nix,
# modules/hjem/look-session.nix, and mango's own config). Only the starting
# mode's theme is applied: DMS keeps one cursor theme, so a runtime mode switch
# doesn't change it.
#
# Opt-out like the other batteries: gated on the master `itera.enable` with
# `mkDefault` values, so it is on by default yet fully overridable.
{
  config,
  lib,
  iteraLib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.cursor;
  look = iteraLib.look.resolve config;
  dconfKeys = l: {
    "org/gnome/desktop/interface" = {
      cursor-theme = l.cursor.name.${l.startMode};
      cursor-size = lib.gvariant.mkInt32 l.cursor.size;
    };
  };
in
{
  options.itera.desktop.cursor.enable = mkOption {
    type = bool;
    default = true;
    description = "Install the look's cursor theme and set it for the session, GTK and XWayland.";
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    # Every itera user's cursor package, so a per-user theme resolves too.
    environment.systemPackages = lib.unique (
      map (n: (look n).cursor.package) ([ null ] ++ lib.attrNames config.itera.users)
    );
    environment.sessionVariables = {
      XCURSOR_THEME = mkDefault (look null).cursor.name.${(look null).startMode};
      XCURSOR_SIZE = mkDefault (toString (look null).cursor.size);
    };

    programs.dconf.enable = mkDefault true;
    programs.dconf.profiles.user.databases = [ { settings = dconfKeys (look null); } ];
    itera.desktop.userDconf = lib.mapAttrs (n: _: dconfKeys (look n)) config.itera.users;
  };
}
