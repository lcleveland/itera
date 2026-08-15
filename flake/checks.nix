{ inputs, ... }:
{
  # `formatting` (treefmt) and `pre-commit` (git-hooks) checks are contributed by
  # their flakeModules. Here we add itera's module regression tests. `nix flake
  # check` is the single entry point that runs all three.
  perSystem =
    { pkgs, lib, ... }:
    let
      # Every `tests/*-eval.nix` is an evaluation check: it builds a NixOS config
      # on `self.nixosModules.default` (via tests/lib.nix) and asserts things
      # about the result. Auto-discovered, like the VM tests below and like the
      # module tree itself — these used to be hand-listed here, which meant a new
      # eval file silently never ran. The check name is the file name minus the
      # extension, so `tests/nh-eval.nix` becomes `checks.<system>.nh-eval`.
      #
      # `tests/lib.nix` and `tests/default.nix` are excluded by the suffix, and
      # `tests/nixos/` holds VM tests rather than evals — none of them match.
      evalChecks = lib.listToAttrs (
        map
          (file: {
            name = lib.strings.removeSuffix ".nix" (baseNameOf (toString file));
            value = import file {
              inherit pkgs lib;
              inherit (inputs) self nixpkgs;
            };
          })
          (
            lib.filter (f: lib.strings.hasSuffix "-eval.nix" (baseNameOf (toString f))) (
              lib.filesystem.listFilesRecursive ../tests
            )
          )
      );
    in
    {
      checks =
        # Auto-discovered VM tests under tests/nixos.
        (import ../tests {
          inherit pkgs lib;
          inherit (inputs) self;
          # VM boot tests need KVM; hosted aarch64 runners have none, so only
          # discover them on x86_64. The eval checks below still run everywhere.
          testDirectory = if pkgs.stdenv.hostPlatform.isx86_64 then ../tests/nixos else ../tests/nonexistent;
        })
        // evalChecks;
    };
}
