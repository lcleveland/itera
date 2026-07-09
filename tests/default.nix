# NixOS integration-test harness for itera's modules.
#
# Auto-discovers every `.nix` file under `testDirectory` and runs it as a real
# NixOS VM test. Each test file returns a partial NixOS test (`nodes` +
# `testScript`) that enables some `hjem.users.<name>.itera.programs.*` option and
# asserts the resulting files/packages/env landed correctly.
#
# `self.nixosModules.default` already imports hjem AND registers itera's home
# layer into `hjem.extraModules`, so simply importing it here also exercises the
# auto-wiring. No test files exist yet — the harness itself is proven by
# `nix flake check`; behavioural tests arrive alongside the curated batteries.
{
  pkgs,
  lib,
  self,
  testDirectory,
}:
let
  nixos-lib = import (pkgs.path + "/nixos/lib") { inherit (pkgs) lib; };

  testFiles =
    if builtins.pathExists testDirectory then
      builtins.filter (p: lib.strings.hasSuffix ".nix" (baseNameOf (toString p))) (
        lib.filesystem.listFilesRecursive testDirectory
      )
    else
      [ ];

  runOne = file: {
    name = lib.strings.removeSuffix ".nix" (baseNameOf (toString file));
    value = nixos-lib.runTest {
      hostPkgs = pkgs;
      name = "itera-${lib.strings.removeSuffix ".nix" (baseNameOf (toString file))}";

      defaults = {
        imports = [ self.nixosModules.default ];

        # disko and impermanence are opt-out (on with itera.enable), but both
        # fight the NixOS test framework's managed disk/root — and disko's
        # assertion fails without a `device`. They get their own dedicated eval
        # (tests/eval.nix) and interactive VM (dev/vm.nix); turn them off for the
        # framework's VM tests so every test node boots the managed root.
        itera = {
          disko.enable = false;
          impermanence.enable = false;
        };

        # A user for tests to configure via `hjem.users.test.itera.*`.
        users.users.test = {
          isNormalUser = true;
          home = "/home/test";
        };
        hjem.users.test.enable = true;
      };

      imports = [ (import file) ];
    };
  };
in
builtins.listToAttrs (map runOne testFiles)
