{ inputs, ... }:
{
  # `formatting` (treefmt) and `pre-commit` (git-hooks) checks are contributed by
  # their flakeModules. Here we add itera's module regression tests. `nix flake
  # check` is the single entry point that runs all three.
  perSystem =
    { pkgs, lib, ... }:
    {
      checks =
        # Auto-discovered VM tests under tests/nixos.
        (import ../tests {
          inherit pkgs lib;
          inherit (inputs) self;
          testDirectory = ../tests/nixos;
        })
        # Evaluation check for the disko + impermanence batteries.
        // {
          disko-impermanence-eval = import ../tests/eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };
        };
    };
}
