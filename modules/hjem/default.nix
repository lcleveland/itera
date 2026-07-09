# itera's per-user home module collection — the value of `hjemModules.default`.
#
# This whole module is appended to `hjem.extraModules`, so it is evaluated
# INSIDE the hjem user submodule. That means the modules it imports write to
# the hjem per-user sinks unprefixed: `packages`, `files`, `xdg.*.files`,
# `environment.sessionVariables`, `warnings`, `assertions`. hjem also provides
# `osConfig`, `osOptions`, `pkgs`, `hjem-lib`, `utils` as module arguments.
{ lib, ... }:
let
  iteraLib = import ../../lib { inherit lib; };
in
{
  # Expose iteraLib to every collection module (mirrors hjem-rum's `rumLib`).
  _module.args.iteraLib = iteraLib;

  # Auto-import every curated program/profile module. `_`-prefixed files (like
  # `programs/_example.nix`) are intentionally skipped.
  imports = iteraLib.modules.listNixModules ./.;
}
