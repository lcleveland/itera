# Curated-program registration for DankMaterialShell (DMS).
#
# Declares DMS's curated settings ONCE and exposes them at two levels:
#   - `itera.programs.dankMaterialShell.*`               — system-wide default
#   - `itera.users.<name>.programs.dankMaterialShell.*`  — per-user override
#
# The hjem battery `modules/hjem/programs/dankmaterialshell.nix` reads the merged
# result via `osConfig` and writes `~/.config/DankMaterialShell/settings.json`
# (and plugin_settings.json).
#
# See lib/programs.nix for the framework. NOT a NixOS module — a registration
# record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkDefault;
  inherit (lib.types)
    attrsOf
    anything
    bool
    either
    package
    path
    submodule
    ;
in
iteraLib.programs.mkCuratedProgram {
  name = "dankMaterialShell";

  fields = {
    settings = {
      type = attrsOf anything;
      attrs = true;
      example = {
        currentThemeName = "blue";
        cornerRadius = 12;
        use24HourClock = true;
      };
      description = ''
        DankMaterialShell settings, written to
        {file}`~/.config/DankMaterialShell/settings.json`. DMS's schema is a flat
        camelCase object, so the system-wide default
        ({option}`itera.programs.dankMaterialShell.settings`) and each per-user
        override merge per key. Keys you do not set fall back to DMS's own runtime
        defaults.
      '';
    };

    plugins = {
      type = attrsOf (submodule {
        options = {
          enable = mkOption {
            type = bool;
            default = true;
            description = ''
              Whether this plugin is installed and enabled. Declaring a plugin ships
              it enabled — set to `false` to turn a default-on plugin off (a per-user
              entry must also re-supply `src`, since a per-user plugin of the same
              name replaces the system entry wholesale).
            '';
          };
          src = mkOption {
            type = either package path;
            description = ''
              Plugin source: a package or a path to the plugin directory (the one
              containing its {file}`plugin.json`). Linked into
              {file}`~/.config/DankMaterialShell/plugins/<name>`.
            '';
          };
          settings = mkOption {
            type = attrsOf anything;
            default = { };
            description = ''
              Per-plugin settings, written under this plugin's key in
              {file}`plugin_settings.json` alongside the derived `enabled` flag.
            '';
          };
        };
      });
      attrs = true;
      example = lib.literalExpression ''
        {
          DockerManager.src = pkgs.fetchFromGitHub {
            owner = "LuckShiba";
            repo = "DmsDockerManager";
            rev = "v1.2.0";
            hash = "sha256-…";
          };
        }
      '';
      description = ''
        DankMaterialShell plugins to install and enable. The system-wide default
        ({option}`itera.programs.dankMaterialShell.plugins`) and each per-user set
        merge per plugin name (a per-user entry of the same name replaces the system
        one wholesale). Each enabled plugin is linked into
        {file}`~/.config/DankMaterialShell/plugins/<name>` and gets a matching
        {file}`plugin_settings.json` entry (`{ enabled = <enable>; } // settings`),
        which wins over any same-named key in
        {option}`itera.programs.dankMaterialShell.pluginSettings`.
      '';
    };

    pluginSettings = {
      type = attrsOf anything;
      attrs = true;
      description = ''
        DankMaterialShell external plugin settings, written to
        {file}`~/.config/DankMaterialShell/plugin_settings.json`. Same per-key merge
        model as {option}`itera.programs.dankMaterialShell.settings`. A raw escape
        hatch — prefer {option}`itera.programs.dankMaterialShell.plugins`, whose
        derived entries override same-named keys here.
      '';
    };
  };

  userExtra = {
    clobber = mkOption {
      type = bool;
      default = true;
      description = ''
        Whether hjem may overwrite an existing settings.json / plugin_settings.json.
        `true` (default): the declarative value always wins (DMS GUI changes reset
        on rebuild). `false`: DMS owns the file after first write and the declarative
        `settings` no longer re-apply.
      '';
    };
  };

  # itera's curated system-wide DMS defaults. Kept intentionally small — pin the
  # settings schema version DMS expects and a couple of opinionated choices;
  # everything else is left to DMS's own runtime defaults. Per-key mkDefault so a
  # consumer overrides individual keys. No null-valued keys (toJSON would emit
  # `null`, which DMS may reject).
  systemConfig = _: {
    settings = {
      configVersion = mkDefault 11;
      use24HourClock = mkDefault true;
      # Dark mode by default: don't follow the desktop portal's color-scheme
      # (which reports "no preference" on a fresh session and would flip DMS to
      # light). With portal sync off, DMS uses its stored isLightMode, which
      # defaults to false (dark).
      syncModeWithPortal = mkDefault false;
      # Weather widget defaults: Fahrenheit and auto-detected location. DMS's own
      # defaults are Celsius (useFahrenheit=false) and a manual location
      # (useAutoLocation=false); auto-location resolves via geoclue, which the
      # desktop battery already enables.
      useFahrenheit = mkDefault true;
      useAutoLocation = mkDefault true;
    };
  };
}
