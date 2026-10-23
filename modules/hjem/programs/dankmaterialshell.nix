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
  pkgs,
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
  batteryOn = b: (osConfig.itera.enable or false) && (osConfig.itera.desktop.${b}.enable or false);

  # The launcher shows this user's Flow mark (docs/look.md#brand-assets) in
  # their starting mode: DMS takes one logo path, so it doesn't follow a live
  # mode switch. DMS keeps logo options on each bar's `launcherButton` entry,
  # so every one gets them, under any keys the entry already sets.
  logo = iteraLib.brand.render pkgs "itera-launcher-logo" 256 256 (
    iteraLib.brand.mark look.startColors
  );
  withLogo =
    w:
    let
      entry =
        if builtins.isString w then
          {
            id = w;
            enabled = true;
          }
        else
          w;
    in
    if entry.id or null == "launcherButton" then
      {
        launcherLogoMode = "custom";
        launcherLogoCustomPath = "${logo}";
      }
      // entry
    else
      w;
  barWithLogo =
    bar:
    bar
    // lib.genAttrs (lib.filter (k: bar ? ${k}) [
      "leftWidgets"
      "centerWidgets"
      "rightWidgets"
    ]) (k: map withLogo bar.${k});

  # Look keys first, so a consumer's own DMS settings (`currentThemeName`,
  # `fontFamily`, …) still win.
  settings = {
    currentThemeName = "custom";
    customThemeFile = "~/.config/${themeFile}";
    fontFamily = look.fonts.sans;
    monoFontFamily = look.fonts.mono;
    lockScreenFontFamily = look.fonts.sans;
    # Layout tokens (docs/look.md#ultrawide). DMS writes the gap to mango's
    # dms/layout.conf; itera never sets a mango gaps line.
    notificationPopupPosition = notificationPositions.${look.layout.notifications};
    mangoLayoutGapsOverride = look.gaps;
  }
  # Icons and cursor only while their batteries install them.
  // lib.optionalAttrs (batteryOn "iconTheme") {
    iconThemePerMode = true;
    iconThemeDark = look.icons.name.dark;
    iconThemeLight = look.icons.name.light;
  }
  // lib.optionalAttrs (batteryOn "cursor") {
    # DMS has one cursor theme, not one per mode: the starting mode's.
    cursorSettings = {
      theme = look.cursor.name.${look.startMode};
      inherit (look.cursor) size;
    };
  }
  // (sys.settings or { })
  // (usr.settings or { });
  # DMS's notificationPopupPosition values (its NotificationsTab), by token.
  notificationPositions = {
    top-right = 0;
    bottom-left = 1;
    top-left = 2;
    bottom-right = 3;
    bottom-center = 5;
    top-center = -1;
  };

  # The bar (docs/look.md#ultrawide): the look's length on every bar, under
  # any keys a bar already sets. With `bar.perOutput`, the first bar is copied
  # once per declared output instead, sized by its aspect class; that needs
  # every declared monitor to have an exact connector name or a model, and a
  # size.
  barLength =
    l:
    if builtins.isInt l then
      {
        barLengthMode = "percent";
        barLengthPercent = l;
      }
    else
      { barLengthMode = l; };
  classLength = {
    standard = "full";
    ultrawide = "full";
    superUltrawide = 60;
  };
  outputs = iteraLib.mango.declaredOutputs (iteraLib.mango.userMonitors osConfig name);
  perOutputWanted = look.layout.bar.perOutput;
  perOutput = perOutputWanted && outputs != [ ] && lib.all iteraLib.mango.keyable outputs;
  globalBars = map (b: barLength look.layout.bar.length // barWithLogo b) settings.barConfigs;
  outputBars = map (
    o:
    barWithLogo (builtins.head settings.barConfigs)
    // {
      id = "itera-${o.screen}";
      name = o.screen;
      screenPreferences = [ o.screen ];
      showOnLastDisplay = false;
    }
    // barLength classLength.${o.class}
  ) outputs;

  finalSettings =
    settings
    // lib.optionalAttrs (settings ? barConfigs && settings.barConfigs != [ ]) {
      barConfigs = if perOutput then outputBars else globalBars;
    };

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
    warnings = lib.optional (perOutputWanted && !perOutput) ''
      the look's bar.perOutput needs every declared mango monitor to have an
      exact connector name or a model, and a width and height; keeping one bar on every
      output.
    '';

    xdg.config.files = {
      "DankMaterialShell/config.d/00-itera.json" = {
        text = builtins.toJSON finalSettings;
        inherit clobber;
      };

      ${themeFile} = {
        text = builtins.toJSON (iteraLib.look.dmsTheme look);
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
