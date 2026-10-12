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

      # Look compliance lints (docs/look.md#verification): grep the source,
      # skipping tests, docs and lib/look.nix, and fail listing every hit.
      # `extraFilter` drops more lines from grep's `file:line:text` output.
      mkLint =
        name:
        {
          pattern,
          extraFilter ? "cat",
          src ? ../.,
        }:
        pkgs.runCommand name { } ''
          cd ${src}
          if grep -rnE --exclude-dir=tests --exclude-dir=docs --exclude='*.md' --exclude=flake.lock \
              -e '${pattern}' . | grep -v '^\./lib/look\.nix:' | ${extraFilter} > $TMPDIR/hits; then
            echo "${name}: found in"; cat $TMPDIR/hits; exit 1
          fi
          touch $out
        '';
      lints = {
        # Colours belong in the palette (lib/look.nix); batteries call `resolve`.
        look-hex-lint = {
          pattern = "#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?\\b";
        };
        # Only lib/look.nix reads `itera.look`. Comment lines don't count.
        look-reads-lint = {
          pattern = "itera\\.(users\\.[^.[:space:]]+\\.)?look\\b";
          extraFilter = "grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'";
        };
      };
    in
    {
      checks =
        lib.mapAttrs mkLint lints
        # Each lint also runs on a planted violation (tests/lint-planted) and
        # must fail on it.
        // lib.mapAttrs' (
          name: lint:
          lib.nameValuePair "${name}-planted" (
            pkgs.testers.testBuildFailure (mkLint name (lint // { src = ../tests/lint-planted; }))
          )
        ) lints
        //
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
