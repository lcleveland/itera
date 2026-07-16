# itera's nh battery: the `nh` Nix CLI helper as the system rebuild + GC tool.
#
# `nh` (https://github.com/nix-community/nh) is a Rust reimplementation of
# `nixos-rebuild` (and `home-manager`/`darwin-rebuild`) that adds a build-tree
# view via nix-output-monitor, a fast generation diff via dix, and a
# confirmation prompt before switching. It also ships `nh clean`, a gcroot-aware
# `nix-collect-garbage` replacement. Turning this on puts `nh` on the system
# PATH; `itera-update` (dev/update-itera.sh) drives `nh os switch`.
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
  inherit (lib.types) bool nullOr str;

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

    flake = mkOption {
      type = nullOr str;
      default = null;
      example = "/home/alice/Documents/itera-config";
      description = ''
        Where {command}`nh` looks for this host's flake when no installable is
        passed, via the `NH_FLAKE` default ({option}`programs.nh.flake`). Leave
        `null` and {command}`nh os switch` (with no argument) falls back to
        {file}`/etc/nixos/flake.nix`, which itera never creates — so bare
        {command}`nh os switch` errors on a fresh install. Set this on a real
        install, normally a path to your persisted config checkout (keep it under
        a persisted path such as {file}`~/Documents` so it survives the ephemeral
        root), so {command}`nh os switch` works with no arguments. The dev test
        hosts leave this `null` because {command}`itera-update` passes the flake
        explicitly.
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

      # `programs.nh.flake` only sets the NH_FLAKE default. nh does NOT discover
      # the running host's flake: with no installable and no NH_FLAKE it falls
      # back to /etc/nixos/flake.nix, which itera never creates (the root is an
      # ephemeral tmpfs), so bare `nh os switch` errors. We surface it as
      # `itera.nix.nh.flake` (null by default) rather than guessing a path — set
      # it on a real install; the test hosts pass the flake via `itera-update`.
      flake = mkIf (cfg.flake != null) (mkDefault cfg.flake);

      clean = {
        enable = mkDefault cfg.clean.enable;
        dates = mkDefault cfg.clean.dates;
        extraArgs = mkDefault cfg.clean.extraArgs;
      };
    };
  };
}
