# itera's DankMaterialShell (DMS) user-config renderer (home layer).
#
# The system battery `itera.desktop.dankMaterialShell` installs the shell; the
# curated-program registration `modules/programs/dankmaterialshell.nix` declares
# the settings (system-wide `itera.programs.dankMaterialShell.*` + per-user
# `itera.users.<name>.programs.dankMaterialShell.*`). THIS battery is the renderer:
# it reads the merged result out of `osConfig` and writes the per-user
# {file}`~/.config/DankMaterialShell/settings.json` (and plugin_settings.json).
#
# Merge model: `systemDefaults // perUserSettings`, a shallow per-key merge. DMS's
# settings schema is a FLAT camelCase object, so this gives exact per-key override
# semantics. Nested values (`cursorSettings`, `barConfigs`, …) are replaced
# wholesale by a per-user override, not deep-merged — expected for a flat schema.
#
# clobber tradeoff: with `clobber = true` (default) hjem symlinks settings.json
# into the read-only Nix store, so the declarative value always wins — DMS GUI
# changes reset on the next rebuild. A per-user `clobber = false` lets DMS own the
# file after first write. The greeter is out of scope — it runs as the `greeter`
# system user, configured via `programs.dms-greeter.*` (the standalone
# dank-greeter module).
#
# Runs inside the hjem user submodule: `xdg.config.files` is unprefixed and
# `osConfig` / `name` are module args. Declares NO options (the schema lives in the
# registration); enablement follows the system desktop toggle.
{
  lib,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.dankMaterialShell.enable or false;

  # System-wide defaults (itera.programs.dankMaterialShell) and this user's
  # overrides. A plain (non-`itera.users`) user has no overrides, so inherits.
  sys = osConfig.itera.programs.dankMaterialShell or { };
  usr = osConfig.itera.users.${name}.programs.dankMaterialShell or { };

  finalSettings = (sys.settings or { }) // (usr.settings or { });
  finalPluginSettings = (sys.pluginSettings or { }) // (usr.pluginSettings or { });
  # Concrete bool (never null): a null would strand the symlink on a stale store path.
  clobber = usr.clobber or true;
in
{
  config = mkIf enable {
    xdg.config.files."DankMaterialShell/settings.json" = mkIf (finalSettings != { }) {
      text = builtins.toJSON finalSettings;
      inherit clobber;
    };

    xdg.config.files."DankMaterialShell/plugin_settings.json" = mkIf (finalPluginSettings != { }) {
      text = builtins.toJSON finalPluginSettings;
      inherit clobber;
    };
  };
}
