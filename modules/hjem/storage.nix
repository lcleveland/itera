# udiskie, the removable-storage automount agent (home layer of `itera.storage`).
#
# A per-user systemd unit bound to the mango session, like DMS and the clipboard
# bridges: wanted by and `PartOf` `mango-session.target`, after `dms.service` so
# its tray icon has a tray to register with, restarted on failure. It stays
# per-user because the tray icon's colour comes from the user's look.
{
  lib,
  pkgs,
  iteraLib,
  osConfig ? null,
  name,
  ...
}:
let
  enable = (osConfig.itera.storage.enable or false) && (osConfig.itera.enable or false);

  # udiskie's tray icon. Left alone it resolves a drive icon from the Qt icon
  # theme (Adwaita), which looks nothing like the DMS bar around it; DMS draws its
  # own icons from Material Symbols Rounded. This is that font's `usb` glyph
  # (Apache-2.0, google/material-design-icons) filled with
  # `itera.storage.trayIconColor`, else this user's look `text` colour in their
  # starting mode (auto starts dark). Qt doesn't recolor icons, so the fill is
  # baked in.
  look = iteraLib.look.resolve osConfig name;
  trayIconColor =
    if osConfig.itera.storage.trayIconColor or null != null then
      osConfig.itera.storage.trayIconColor
    else
      look.startColors.text;
  udiskieIcon = pkgs.writeText "udiskie-tray-icon.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path fill="${trayIconColor}" d="M480-80q-33 0-56.5-23.5T400-160q0-21 11-39t29-29v-92H320q-33 0-56.5-23.5T240-400v-92q-18-9-29-27t-11-41q0-33 23.5-56.5T280-640q33 0 56.5 23.5T360-560q0 23-11 40t-29 28v92h120v-320h-40q-12 0-18-11t2-21l80-107q6-8 16-8t16 8l80 107q8 10 2 21t-18 11h-40v320h120v-80h-20q-8 0-14-6t-6-14v-120q0-8 6-14t14-6h120q8 0 14 6t6 14v120q0 8-6 14t-14 6h-20v80q0 33-23.5 56.5T640-320H520v92q19 10 29.5 28t10.5 40q0 33-23.5 56.5T480-80Z"/></svg>
  '';
  # udiskie accepts a file path in `icon_names`, and DMS's tray loads a path icon
  # as a file. `-c` means a ~/.config/udiskie/config.yml is not read.
  udiskieConfig = pkgs.writeText "udiskie-config.yml" ''
    icon_names:
      media:
        - ${udiskieIcon}
  '';
in
{
  config = lib.mkIf enable {
    systemd.services.udiskie = {
      description = "udiskie removable-storage automounter";
      wantedBy = [ "mango-session.target" ];
      partOf = [ "mango-session.target" ];
      after = [ "dms.service" ];
      serviceConfig = {
        # --appindicator: without WAYLAND_DISPLAY in the unit's environment udiskie
        # silently falls back to a GTK tray icon that DMS doesn't show.
        ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --tray --appindicator -c ${udiskieConfig}";
        Restart = "on-failure";
      };
    };
  };
}
