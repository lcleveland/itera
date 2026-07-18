# itera's nh battery: the `nh` Nix CLI helper as the system rebuild + GC tool.
#
# `nh` (https://github.com/nix-community/nh) is a Rust reimplementation of
# `nixos-rebuild` (and `home-manager`/`darwin-rebuild`) that adds a build-tree
# view via nix-output-monitor, a fast generation diff via dix, and a
# confirmation prompt before switching. It also ships `nh clean`, a gcroot-aware
# `nix-collect-garbage` replacement. Turning this on puts `nh` on the system
# PATH; `itera-update` (dev/update-itera.sh) drives `nh os switch`. Which flake
# and configuration `nh` builds is configured by the update battery
# (`itera.update.*`, modules/nixos/core/update.nix).
#
# GC division of labour with `gc.nix`: when `clean.enable` is on (the default),
# `nh clean` owns scheduled garbage collection and `gc.nix` steps its
# `nix.gc.automatic` timer aside — the two would otherwise fight, and the
# upstream `programs.nh` module asserts against running both. `nh clean` does not
# optimise the store, so `gc.nix` keeps `nix.optimise.automatic` regardless.
#
# Follows the opt-out shape of the other core batteries (see `gc.nix`,
# `nix.nix`): gated on the master `itera.enable` with per-feature `enable`
# toggles (default true), values set with `mkDefault` so a consumer can override
# any of them.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool str;

  cfg = config.itera.nix.nh;
in
{
  options.itera.nix.nh = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable the {command}`nh` Nix CLI helper. On by default whenever
        {option}`itera.enable` is set; set this to `false` to fall back to plain
        {command}`nixos-rebuild` (and, if {option}`itera.nix.gc.enable` is on,
        the standard {command}`nix-collect-garbage` timer).
      '';
    };

    clean = {
      enable = mkOption {
        type = bool;
        default = true;
        description = ''
          Run periodic garbage collection with {command}`nh clean` instead of
          the {option}`nix.gc` timer. When on, {file}`gc.nix` disables
          {option}`nix.gc.automatic` so the two GC schedulers don't conflict
          (the store-optimisation pass in {file}`gc.nix` is unaffected). Set to
          `false` to leave scheduled GC to {option}`itera.nix.gc`.
        '';
      };

      dates = mkOption {
        type = str;
        default = "weekly";
        example = "daily";
        description = ''
          How often {command}`nh clean` runs, as a systemd calendar spec (see
          {manpage}`systemd.time(7)`). Passed to {option}`programs.nh.clean.dates`.
        '';
      };

      extraArgs = mkOption {
        type = str;
        default = "--keep-since 14d --keep 3";
        example = "--keep-since 30d --keep 5";
        description = ''
          Flags for {command}`nh clean all` when run on a schedule. Defaults to
          keeping everything from the last two weeks plus a floor of three
          generations — the same two-week retention intent as
          {option}`itera.nix.gc.options`, with a safety floor so a rarely-rebuilt
          host is never left with a single generation. Passed to
          {option}`programs.nh.clean.extraArgs`.
        '';
      };
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    programs.nh = {
      enable = mkDefault true;

      # The NH_FLAKE default (`programs.nh.flake`) — which flake a bare `nh os
      # switch` resolves — is owned by the update battery (`itera.update.flake`,
      # modules/nixos/core/update.nix), alongside the configuration name the
      # `itera` command builds.

      clean = {
        enable = mkDefault cfg.clean.enable;
        dates = mkDefault cfg.clean.dates;
        extraArgs = mkDefault cfg.clean.extraArgs;
      };
    };
  };
}
