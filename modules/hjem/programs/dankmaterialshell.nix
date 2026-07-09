# itera's DankMaterialShell (DMS) user-config battery (home layer).
#
# The system battery `itera.desktop.dankMaterialShell` installs the shell and
# holds the system-wide default settings; this hjem battery writes the per-user
# {file}`~/.config/DankMaterialShell/settings.json` (and plugin_settings.json)
# that DMS actually reads. Because itera's home collection is applied to every
# hjem user, enabling the desktop is enough for every user to inherit the
# system-wide defaults — no per-user wiring needed.
#
# Merge model: the file content is `systemDefaults // perUserSettings`, a shallow
# merge. DMS's settings schema is a FLAT camelCase object, so this gives exact
# per-key override semantics (setting `cornerRadius` changes only that key).
# Keys whose values are themselves attrsets/lists (`cursorSettings`, `barConfigs`,
# `notificationRules`, …) are replaced wholesale by a per-user override, not
# deep-merged — expected for a flat JSON schema.
#
# clobber tradeoff: with `clobber = true` (default) hjem symlinks settings.json
# into the read-only Nix store, so the declarative value always wins — changes
# made in the DMS settings GUI are ephemeral and reset on the next rebuild. Set
# `clobber = false` to let DMS own the file after first write (your declarative
# `settings` then no longer re-apply on rebuild). The greeter is out of scope of
# this battery — it runs as the `greeter` system user and is configured via the
# `programs.dank-material-shell.greeter.*` options.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks
# like `xdg.config.files` are unprefixed and `osConfig` / `pkgs` are module args.
# Enable tracks the system toggle by default.
{
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool attrsOf anything;

  cfg = config.itera.programs.dankMaterialShell;

  systemDefaults = osConfig.itera.desktop.dankMaterialShell.settings or { };
  systemPluginDefaults = osConfig.itera.desktop.dankMaterialShell.pluginSettings or { };
  systemEnabled = osConfig.itera.desktop.dankMaterialShell.enable or false;

  finalSettings = systemDefaults // cfg.settings;
  finalPluginSettings = systemPluginDefaults // cfg.pluginSettings;
in
{
  options.itera.programs.dankMaterialShell = {
    enable =
      mkEnableOption "itera's DankMaterialShell user configuration"
      # Follow the system desktop toggle by default: enabling
      # `itera.desktop.dankMaterialShell` is enough to get the matching home config.
      // {
        default = systemEnabled;
        defaultText = lib.literalExpression "osConfig.itera.desktop.dankMaterialShell.enable";
      };

    settings = mkOption {
      type = attrsOf anything;
      default = { };
      example = {
        cornerRadius = 8;
        currentThemeName = "blue";
      };
      description = ''
        Per-user DankMaterialShell settings, merged on top of the system-wide
        defaults ({option}`itera.desktop.dankMaterialShell.settings`) with a
        shallow `//`. Set individual keys to deviate from the system defaults.
      '';
    };

    pluginSettings = mkOption {
      type = attrsOf anything;
      default = { };
      description = "Per-user external plugin settings, merged over the system-wide `pluginSettings`.";
    };

    clobber = mkOption {
      type = bool;
      default = true;
      description = ''
        Whether hjem may overwrite an existing settings.json / plugin_settings.json.
        `true` (default): the declarative value always wins (DMS GUI changes are
        reset on rebuild). `false`: DMS owns the file after first write and the
        declarative `settings` no longer re-apply.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Warn (don't fail) if the home config is on but the system desktop is off —
    # the settings.json would be written for a shell that isn't installed.
    warnings = lib.optional (!systemEnabled) ''
      itera.programs.dankMaterialShell is enabled for a user but
      itera.desktop.dankMaterialShell.enable is false — the DMS settings will be
      written to $HOME without the shell being installed.
    '';

    xdg.config.files."DankMaterialShell/settings.json" = mkIf (finalSettings != { }) {
      text = builtins.toJSON finalSettings;
      inherit (cfg) clobber;
    };

    xdg.config.files."DankMaterialShell/plugin_settings.json" = mkIf (finalPluginSettings != { }) {
      text = builtins.toJSON finalPluginSettings;
      inherit (cfg) clobber;
    };
  };
}
