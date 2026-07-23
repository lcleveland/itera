# itera's DankMaterialShell (DMS) user-config renderer (home layer).
#
# The system battery `itera.desktop.dankMaterialShell` installs the shell; the
# curated-program registration `modules/programs/dankmaterialshell.nix` declares
# the settings (system-wide `itera.programs.dankMaterialShell.*` + per-user
# `itera.users.<name>.programs.dankMaterialShell.*`). THIS battery is the renderer:
# it reads the merged result out of `osConfig` and writes the per-user
# {file}`~/.config/DankMaterialShell/settings.json` (and plugin_settings.json), and
# links each enabled plugin's source into
# {file}`~/.config/DankMaterialShell/plugins/<name>`, deriving its plugin_settings.json
# entry (`{ enabled; } // settings`).
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

  # Plugins: per-name merge (a per-user entry of the same name replaces the system
  # one wholesale), same model as settings and mango's monitors/gestures.
  finalPlugins = (sys.plugins or { }) // (usr.plugins or { });
  enabledPlugins = lib.filterAttrs (_: p: p.enable) finalPlugins;

  # Derived plugin_settings.json entries: `{ enabled = <enable>; } // settings`.
  # Explicitly-disabled plugins are kept as `{ enabled = false; }` so turning a
  # default-on plugin off per-user propagates a concrete `enabled = false` rather
  # than silently dropping the key. The raw `pluginSettings` escape hatch comes
  # first so structured `plugins` entries win per key.
  derivedPluginSettings = lib.mapAttrs (_: p: { enabled = p.enable; } // p.settings) finalPlugins;
  finalPluginSettings =
    (sys.pluginSettings or { }) // (usr.pluginSettings or { }) // derivedPluginSettings;

  # Concrete bool (never null): a null would strand the symlink on a stale store path.
  clobber = usr.clobber or true;
in
{
  config = mkIf enable {
    xdg.config.files = {
      "DankMaterialShell/settings.json" = mkIf (finalSettings != { }) {
        text = builtins.toJSON finalSettings;
        inherit clobber;
      };

      "DankMaterialShell/plugin_settings.json" = mkIf (finalPluginSettings != { }) {
        text = builtins.toJSON finalPluginSettings;
        inherit clobber;
      };
    }
    # Link each enabled plugin's source directory into
    # ~/.config/DankMaterialShell/plugins/<name> (hjem's `source` accepts a dir).
    // lib.mapAttrs' (name: p: {
      name = "DankMaterialShell/plugins/${name}";
      value = {
        source = p.src;
        inherit clobber;
      };
    }) enabledPlugins;
  };
}
