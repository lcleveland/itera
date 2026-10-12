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
        radiusStrength = 50;
        clockFormat = "24h";
      };
      description = ''
        DankMaterialShell settings, written to
        {file}`~/.config/DankMaterialShell/config.d/00-itera.json`, a drop-in DMS
        layers over its own {file}`settings.json`. Keys set here win over the DMS
        GUI (an edit lasts until DMS restarts); every other GUI change persists in
        settings.json. DMS's schema is a flat camelCase object, so the system-wide
        default ({option}`itera.programs.dankMaterialShell.settings`) and each
        per-user override merge per key. Keys you do not set fall back to DMS's own
        runtime defaults.
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
        Whether hjem may overwrite an existing config.d/00-itera.json /
        plugin_settings.json. `true` (default): the declarative value always wins.
        `false`: DMS owns the files after first write and the declarative
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
      # `configVersion` is pinned by the desktop battery to the bundled DMS's
      # current schema version (read from its source), so DMS never migrates.
      clockFormat = mkDefault "24h";
      # DMS owns the live mode (seeded from `look.mode`, see
      # modules/hjem/look-seed.nix) and writes it to the portal color-scheme,
      # which GTK, libadwaita and Flatpak apps follow.
      syncModeWithPortal = mkDefault true;
      # Weather widget defaults: Fahrenheit and auto-detected location. DMS's own
      # defaults are Celsius (useFahrenheit=false) and a manual location
      # (useAutoLocation=false); auto-location resolves via geoclue, which the
      # desktop battery already enables.
      useFahrenheit = mkDefault true;
      useAutoLocation = mkDefault true;
      # Idle: DMS handles idle itself, and its defaults never lock, blank or
      # suspend. Seconds, picked from the values DMS's Power settings offer. No
      # suspend on AC (a desktop may be serving something).
      acLockTimeout = mkDefault 600;
      acMonitorTimeout = mkDefault 900;
      batteryLockTimeout = mkDefault 300;
      batteryMonitorTimeout = mkDefault 600;
      batterySuspendTimeout = mkDefault 1800;
      lockBeforeSuspend = mkDefault true;
      # DMS already notifies at critical battery; also warn at low.
      batteryNotifyLow = mkDefault true;
    };
  };
}
