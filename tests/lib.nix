# Shared scaffolding for itera's `*-eval` checks.
#
# Every eval check builds a NixOS configuration on top of
# `self.nixosModules.default` and then asserts things about the generated
# `config`. This module factors out the two pieces they all repeated:
#
#   - `mkConfig`: evaluate a config with itera on and a pinned stateVersion,
#     returning `.config`. disko + impermanence are defaulted OFF (via
#     `mkDefault`) since most checks don't want a device assertion / tmpfs root;
#     a check that needs them (see disko-impermanence-eval.nix,
#     integrations-eval.nix) turns them on with `diskoOn` below.
#   - `diskoOn`: the module that flips disko + impermanence back on, with a
#     device set. Shared so the two checks that need it can't drift apart.
#   - `hasPkgName` / `hasPkgInfix`: the two package-list predicates the checks
#     kept redefining. They are NOT interchangeable — see their notes.
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

  # Turn disko + impermanence back on (overriding mkConfig's mkDefault-off) so a
  # check exercises partitioning and the tmpfs root. Layer it into the module
  # list: `mkConfig [ diskoOn { … } ]`.
  diskoOn = {
    itera.disko = {
      enable = true;
      device = "/dev/vda";
    };
    itera.impermanence.enable = true;
  };

  # Exact match on the derivation's parsed name, e.g. `hasPkgName "git"`. Use
  # this by default — it cannot match a package by accident.
  hasPkgName = name: pkgList: builtins.elem name (map lib.getName pkgList);

  # Looser: exact `pname` OR a substring of the full name-with-version. Needed
  # where the attribute and the derivation name disagree — e.g. matching
  # "jetbrains-mono" against the nerd-font package in `fonts.packages`. Prefer
  # `hasPkgName` unless a check actually needs this.
  hasPkgInfix =
    pname: pkgList:
    builtins.any (p: (p.pname or p.name or "") == pname || lib.hasInfix pname (p.name or "")) pkgList;

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
