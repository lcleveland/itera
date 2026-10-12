# Per-user dconf defaults for itera users.
#
# The system dconf database (`programs.dconf.profiles.user`) is one floor for
# every account, but the look is per user. dconf reads the profile at
# `$XDG_RUNTIME_DIR/dconf/profile` before the shared `user` one, so each itera
# user with keys here gets a profile `itera-<name>`: their own writable
# database first, then a read-only database of these keys, then the system
# databases. The user's own gsettings changes still win; these are defaults.
# A user tmpfiles rule links the profile into place at login.
#
# Batteries add keys under `itera.desktop.userDconf.<name>.<dir>.<key>`, as the
# icon-theme and cursor batteries do from each user's look.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) attrsOf anything;

  cfg = config.itera.desktop.userDconf;
in
{
  options.itera.desktop.userDconf = mkOption {
    type = attrsOf (attrsOf (attrsOf anything));
    default = { };
    internal = true;
    description = ''
      Per-user dconf defaults: user name, then dconf directory, then key. Layered
      under the user's own dconf database and over the system databases.
    '';
  };

  config = mkIf (cfg != { }) {
    programs.dconf.enable = mkDefault true;

    programs.dconf.profiles = lib.mapAttrs' (
      name: settings:
      lib.nameValuePair "itera-${name}" {
        enableUserDb = true;
        databases = [ { inherit settings; } ] ++ config.programs.dconf.profiles.user.databases or [ ];
      }
    ) cfg;

    systemd.user.tmpfiles.users = lib.mapAttrs (name: _: {
      rules = [ "L+ %t/dconf/profile - - - - /etc/dconf/profile/itera-${name}" ];
    }) cfg;
  };
}
