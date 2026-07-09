# REFERENCE ONLY — this file is `_`-prefixed so it is NOT auto-imported.
#
# It documents the convention every itera "battery" (curated per-program home
# module) follows. To ship a real battery, copy this into a non-underscore file
# (e.g. `programs/helix.nix`), rename the namespace, and fill in the config.
#
# Reminder: this module runs inside the hjem user submodule, so the full
# downstream option path is `hjem.users.<name>.itera.programs.<name>` and the
# sinks (`packages`, `xdg.config.files`, `environment.sessionVariables`, …) are
# written unprefixed. Available module args include `config`, `lib`, `pkgs`,
# `osConfig`, `osOptions`, `hjem-lib`, `utils`, and itera's `iteraLib`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkEnableOption mkOption mkPackageOption;
  inherit (lib.modules) mkIf mkDefault;

  # Structured settings serialised with nixpkgs' format generators.
  toml = pkgs.formats.toml { };

  cfg = config.itera.programs.example;
in
{
  options.itera.programs.example = {
    enable = mkEnableOption "the example program, configured with itera defaults";

    # `nullable = true` lets a user drop the package (e.g. to supply their own).
    package = mkPackageOption pkgs "hello" { nullable = true; };

    settings = mkOption {
      inherit (toml) type;
      default = { };
      example = {
        theme = "itera";
        greeting = "hei";
      };
      description = ''
        Written verbatim to {file}`$XDG_CONFIG_HOME/example/config.toml`.
        itera's opinionated defaults are merged underneath via `mkDefault`, so
        anything set here wins — the module stays opt-out.
      '';
    };
  };

  config = mkIf cfg.enable {
    # hjem sink: per-user packages.
    packages = mkIf (cfg.package != null) [ cfg.package ];

    # hjem sink: per-user session variables.
    environment.sessionVariables.EXAMPLE_CONFIGURED = "1";

    # Opinionated "batteries-included" defaults; explicit user values override.
    itera.programs.example.settings = {
      theme = mkDefault "itera";
      greeting = mkDefault "hei";
    };

    # hjem sink: an XDG config file generated from the merged settings.
    xdg.config.files."example/config.toml" = mkIf (cfg.settings != { }) {
      source = toml.generate "example-config.toml" cfg.settings;
    };
  };
}
