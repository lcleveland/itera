# itera's command-lookup battery (nix-index + comma).
#
# A thin wrapper over nix-index-database (bundled by `modules/nixos/default.nix`),
# which ships a weekly-prebuilt nix-index database in the Nix store. That gives:
#   - a working `command-not-found` handler that suggests the package (and the
#     `nix-shell`/`nix run` invocation) for a missing command, and
#   - `comma` (`,`) plus `nix-locate`, to run any package without installing it.
#
# Because the database rides in via the flake input (store path), there is nothing
# to build or persist — it composes with impermanence for free.
#
# Opt-OUT (default ON): pure quality-of-life, low risk. Set
# `itera.nixIndex.enable = false` to drop it.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.nixIndex;
in
{
  options.itera.nixIndex = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable the prebuilt nix-index database, `command-not-found`, and `comma`.
        On by default whenever {option}`itera.enable` is set; set to `false` to
        opt out.
      '';
    };

    comma = mkOption {
      type = bool;
      default = true;
      description = "Also install `comma` (`,`) to run packages without installing them.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    programs.nix-index.enable = mkDefault true;
    programs.nix-index-database.comma.enable = mkDefault cfg.comma;
  };
}
