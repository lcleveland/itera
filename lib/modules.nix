{ lib }:
let
  inherit (lib.filesystem) listFilesRecursive;
  inherit (lib.strings) hasSuffix hasPrefix;
in
{
  # Recursively collect every importable `.nix` module under `dir`, ready to be
  # spliced into a module's `imports`. Skips:
  #   - `default.nix` (the aggregator that usually calls this helper itself), and
  #   - any `_`-prefixed file (private helpers / work-in-progress not yet shipped).
  #
  # This is what makes adding a module a matter of "drop a `.nix` file in the
  # right directory" — no manual wiring anywhere.
  #
  # NOTE: the filter matches on the file basename only; `listFilesRecursive`
  # still descends into `_`-prefixed directories. Prefix WIP *files*, or extend
  # this to test path components if you later need directory-level exclusion.
  listNixModules =
    dir:
    builtins.filter (
      path:
      let
        base = baseNameOf (toString path);
      in
      hasSuffix ".nix" base && base != "default.nix" && !hasPrefix "_" base
    ) (listFilesRecursive dir);
}
