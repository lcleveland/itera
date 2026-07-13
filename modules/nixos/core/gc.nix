# itera's nix garbage-collection battery: automatic GC + store optimisation.
#
# Without this, the Nix store grows without bound: old system generations pile up
# and identical store paths are stored once per closure. This schedules
# `nix-collect-garbage`, dropping generations older than two weeks, and a store
# optimisation pass that hardlinks identical paths together.
#
# Follows the opt-out shape of the other core batteries (see `cache.nix`): gated
# on the master `itera.enable` with a per-feature `enable` (default true), so it
# comes along automatically but is fully overridable. Values use `mkDefault` so a
# consuming host can override any of them.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool str;

  cfg = config.itera.nix.gc;
in
{
  options.itera.nix.gc = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable automatic Nix garbage collection. On by default whenever
        {option}`itera.enable` is set; set this to `false` to leave the store
        untouched and collect garbage manually.
      '';
    };

    dates = mkOption {
      type = str;
      default = "weekly";
      example = "daily";
      description = ''
        How often to run garbage collection, as a systemd calendar spec (see
        {manpage}`systemd.time(7)`). Passed to {option}`nix.gc.dates`.
      '';
    };

    options = mkOption {
      type = str;
      default = "--delete-older-than 14d";
      example = "--delete-older-than 30d";
      description = ''
        Extra flags for {command}`nix-collect-garbage`. Defaults to deleting
        system generations older than two weeks. Passed to
        {option}`nix.gc.options`.
      '';
    };

    optimise.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Run a scheduled Nix store optimisation pass that hardlinks identical
        store paths together to save disk. Uses {option}`nix.optimise.automatic`
        rather than build-time `auto-optimise-store` to avoid the per-build
        locking penalty.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    nix.gc = {
      automatic = mkDefault true;
      dates = mkDefault cfg.dates;
      options = mkDefault cfg.options;
    };

    nix.optimise.automatic = mkDefault cfg.optimise.enable;
  };
}
