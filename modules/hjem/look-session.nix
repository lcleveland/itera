# The look's per-user session environment (home layer).
#
# Writes this user's starting-mode cursor and icon theme where the session reads
# them: `~/.config/environment.d` (the systemd user manager applies it to
# dms.service and every app launched from it) and `~/.Xresources` (XWayland
# apps). The system batteries set the same variables from the system look as
# the floor (modules/nixos/desktop/cursor.nix, icon-theme.nix).
{
  lib,
  iteraLib,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  on = b: (osConfig.itera.enable or false) && (osConfig.itera.desktop.${b}.enable or false);
  cursorOn = on "cursor";
  iconsOn = on "iconTheme";

  look = iteraLib.look.resolve osConfig name;
  cursorName = look.cursor.name.${look.startMode};
  env =
    lib.optionalAttrs cursorOn {
      XCURSOR_THEME = cursorName;
      XCURSOR_SIZE = toString look.cursor.size;
    }
    // lib.optionalAttrs iconsOn { QS_ICON_THEME = look.icons.name.${look.startMode}; };
in
{
  config = {
    xdg.config.files."environment.d/60-itera-look.conf" = mkIf (env != { }) {
      text = lib.concatLines (lib.mapAttrsToList (k: v: "${k}=${v}") env);
    };

    # A writable copy, not a store link: DMS rewrites it (and runs `xrdb -merge`)
    # when the cursor is changed in its GUI, which lasts until the next
    # activation.
    files.".Xresources" = mkIf cursorOn {
      type = "copy";
      permissions = "0644";
      text = ''
        Xcursor.theme: ${cursorName}
        Xcursor.size: ${toString look.cursor.size}
      '';
    };
  };
}
