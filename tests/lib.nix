# Shared scaffolding for itera's `*-eval` checks.
#
# Every eval check builds a NixOS configuration on top of
# `self.nixosModules.default` and then asserts things about the generated
# `config`. This module factors out the two pieces they all repeated:
#
#   - `mkConfig`: evaluate a config with itera on and a pinned stateVersion,
#     returning `.config`. disko + impermanence are defaulted OFF (via
#     `mkDefault`) since most checks don't want a device assertion / tmpfs root;
#     a check that needs them (see tests/eval.nix, integrations-eval.nix) just
#     turns them on in its own module list, which overrides the default.
#   - `mkCheckDrv`: the `failed`-attrs → `runCommand`/`throw` tail.
#
# NOT a discovered check itself: flake/checks.nix imports each eval file by name,
# and tests/default.nix only scans tests/nixos/, so this helper is never run as a
# test on its own.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
{
  # extraModules :: list of NixOS modules layered on top of the itera base.
  # Returns the evaluated `.config`.
  mkConfig =
    extraModules:
    (nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.default
        {
          system.stateVersion = "25.05";
          itera = {
            enable = true;
            # Off by default so disko's device assertion doesn't block evals that
            # only exercise other batteries; a check needing them sets them on.
            disko.enable = lib.mkDefault false;
            impermanence.enable = lib.mkDefault false;
          };
        }
      ]
      ++ extraModules;
    }).config;

  # name :: derivation name, also used in the failure message.
  # checks :: attrset of <description> -> <bool>. Fails loudly listing every
  # false entry; otherwise produces an empty output.
  mkCheckDrv =
    name: checks:
    let
      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
    in
    pkgs.runCommand name { } (
      if failed == [ ] then "touch $out" else throw "${name} failed: ${lib.concatStringsSep "; " failed}"
    );
}
