# Evaluation check for the nh battery (modules/nixos/core/nh.nix) and its GC
# hand-off with the gc battery (modules/nixos/core/gc.nix).
#
# nh drives no bootable service worth a VM test; what matters is the wiring:
# nh is on by default, `nh clean` owns scheduled GC (so `nix.gc.automatic` steps
# aside to avoid the upstream conflict assertion), the store-optimise pass stays
# on regardless, and turning either toggle off restores the plain `nix.gc` timer.
# We evaluate a few NixOS configurations and assert the generated config; `nix
# build` forces evaluation and fails loudly on any false assertion.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;

  # Defaults: nh on, nh clean owns GC.
  base = mkConfig [ ];

  # nh on but its scheduled clean turned off: GC falls back to the nix.gc timer.
  cleanOff = mkConfig [ { itera.nix.nh.clean.enable = false; } ];

  # nh battery off entirely: no nh, GC falls back to the nix.gc timer.
  nhOff = mkConfig [ { itera.nix.nh.enable = false; } ];

  checks = {
    # --- defaults: nh on, nh clean owns GC ---
    "nh is enabled by default" = base.programs.nh.enable;
    "nh clean is enabled by default" = base.programs.nh.clean.enable;
    "nh clean retention keeps the two-week / floor-of-3 default" =
      base.programs.nh.clean.extraArgs == "--keep-since 14d --keep 3";
    "nix.gc timer steps aside when nh clean owns GC" = !base.nix.gc.automatic;
    "store optimisation stays on under nh clean" = base.nix.optimise.automatic;
    "nh flake is unset by default (bare nh os switch left to nh's own default)" =
      base.programs.nh.flake == null;

    # --- nh clean off: GC falls back to the nix.gc timer ---
    "nh stays on when only clean is disabled" = cleanOff.programs.nh.enable;
    "nh clean off leaves programs.nh.clean disabled" = !cleanOff.programs.nh.clean.enable;
    "nix.gc timer runs when nh clean is off" = cleanOff.nix.gc.automatic;

    # --- nh battery off: GC falls back to the nix.gc timer ---
    "nh is off when the battery is disabled" = !nhOff.programs.nh.enable;
    "programs.nh.clean stays off when the battery is disabled" = !nhOff.programs.nh.clean.enable;
    "nix.gc timer runs when the nh battery is off" = nhOff.nix.gc.automatic;
  };

in
mkCheckDrv "itera-nh-eval" checks
