# itera's icon-theme battery.
#
# The Wayland desktop is Quickshell/Qt-based (DankMaterialShell). Quickshell
# resolves system-tray (SNI) icon *names* — other apps' tray icons (udiskie ships its
# own, see `modules/hjem/programs/mango.nix`),
# DMS's own menu icons — through the Qt icon theme. This battery installs the
# look's icon theme (Papirus with teal folders by default) and names it: for the
# shell (`QS_ICON_THEME`, honoured by Quickshell, set per user by
# modules/hjem/look-session.nix with the system look as the floor) and for GTK
# (dconf `icon-theme`, system floor plus each user's own). DMS swaps the theme
# per mode itself (modules/hjem/programs/dankmaterialshell.nix).
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

  cfg = config.itera.desktop.iconTheme;
  look = iteraLib.look.resolve config;
  iconName = l: l.icons.name.${l.startMode};
in
{
  options.itera.desktop.iconTheme.enable = mkOption {
    type = bool;
    default = true;
    description = ''
      Install the look's icon theme so desktop/tray (SNI) icons resolve, and name
      it for Quickshell, GTK and DMS.
    '';
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    # Every itera user's icon package, so a per-user theme resolves too.
    environment.systemPackages = lib.unique (
      map (n: (look n).icons.package) ([ null ] ++ lib.attrNames config.itera.users)
    );
    environment.sessionVariables.QS_ICON_THEME = mkDefault (iconName (look null));

    programs.dconf.enable = mkDefault true;
    programs.dconf.profiles.user.databases = [
      { settings."org/gnome/desktop/interface".icon-theme = iconName (look null); }
    ];
    itera.desktop.userDconf = lib.mapAttrs (n: _: {
      "org/gnome/desktop/interface".icon-theme = iconName (look n);
    }) config.itera.users;
  };
}
