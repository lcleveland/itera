{ inputs, ... }:
{
  # `formatting` (treefmt) and `pre-commit` (git-hooks) checks are contributed by
  # their flakeModules. Here we add itera's module regression tests. `nix flake
  # check` is the single entry point that runs all three.
  perSystem =
    { pkgs, lib, ... }:
    {
      checks = import ../tests {
        inherit pkgs lib;
        inherit (inputs) self;
        testDirectory = ../tests/nixos;
      };
    };
}
