# itera's DankMaterialShell (DMS) user-config renderer (home layer).
#
# The system battery `itera.desktop.dankMaterialShell` installs the shell; the
# curated-program registration `modules/programs/dankmaterialshell.nix` declares
# the settings (system-wide `itera.programs.dankMaterialShell.*` + per-user
# `itera.users.<name>.programs.dankMaterialShell.*`). THIS battery is the renderer:
# it reads the merged result out of `osConfig` and writes the per-user
# {file}`~/.config/DankMaterialShell/config.d/00-itera.json` (and
# plugin_settings.json), and
# links each enabled plugin's source into
# {file}`~/.config/DankMaterialShell/plugins/<name>`, deriving its plugin_settings.json
# entry (`{ enabled; } // settings`).
#
# Merge model: `systemDefaults // perUserSettings`, a shallow per-key merge. DMS's
# settings schema is a FLAT camelCase object, so this gives exact per-key override
# semantics. Nested values (`cursorSettings`, `barConfigs`, …) are replaced
# wholesale by a per-user override, not deep-merged — expected for a flat schema.
#
# Why config.d and not settings.json: DMS layers every
# {file}`config.d/*.json` over {file}`settings.json` (later files win) and saves
# each key back to the highest file that defines it, sending keys no file defines
# to settings.json. So itera's keys live in a read-only drop-in and settings.json
# stays a plain file DMS owns: GUI changes to anything itera does not set persist,
# while itera's keys still win (a GUI edit to one lasts until DMS restarts). The
# drop-in carries the current `configVersion`, so DMS never migrates it.
#
# clobber tradeoff: with `clobber = true` (default) hjem symlinks the drop-in into
# the read-only Nix store, so the declarative value always wins. A per-user
# `clobber = false` lets DMS own it after first write. The greeter reads the same
# merged settings via `programs.dms-greeter` (see the desktop battery).
#
# Runs inside the hjem user submodule: `xdg.config.files` is unprefixed and
# `osConfig` / `name` are module args. Declares NO options (the schema lives in the
# registration); enablement follows the system desktop toggle.
{
  lib,
  iteraLib,
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

  # The DMS lane's source: this user's look as a DMS custom theme, both modes,
  # through the DMS mapping in docs/look.md#palette-tide. DMS picks the mode.
  look = iteraLib.look.resolve osConfig name;
  themeFile = "DankMaterialShell/itera-theme.json";
  dmsTheme = c: {
    primary = c.accent;
    primaryText = c.textOnAccent;
    primaryContainer = c.accentContainer;
    primaryContainerText = c.textOnAccentContainer;
    secondary = c.accentSecondary;
    tertiary = c.accentTertiary;
    surfaceTint = c.accent;
    surface = c.background;
    surfaceContainerLowest = c.surface.lowest;
    surfaceContainerLow = c.surface.low;
    surfaceContainer = c.surface.base;
    surfaceContainerHigh = c.surface.high;
    surfaceContainerHighest = c.surface.highest;
    inherit (c) surfaceVariant;
    surfaceText = c.text;
    surfaceVariantText = c.textMuted;
    inherit (c) background;
    backgroundText = c.text;
    inherit (c) inverseSurface;
    inverseOnSurface = c.inverseText;
    outline = c.border;
    inherit (c)
      error
      warning
      success
      info
      scrim
      ;
  };

  # Look keys first, so a consumer's own DMS settings (`currentThemeName`,
  # `fontFamily`, …) still win.
  finalSettings = {
    currentThemeName = "custom";
    customThemeFile = "~/.config/${themeFile}";
    fontFamily = look.fonts.sans;
    monoFontFamily = look.fonts.mono;
    lockScreenFontFamily = look.fonts.sans;
  }
  // (sys.settings or { })
  // (usr.settings or { });

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
      "DankMaterialShell/config.d/00-itera.json" = {
        text = builtins.toJSON finalSettings;
        inherit clobber;
      };

      ${themeFile} = {
        text = builtins.toJSON {
          name = "itera";
          dark = dmsTheme look.colors.dark;
          light = dmsTheme look.colors.light;
        };
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
