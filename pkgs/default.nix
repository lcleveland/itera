# itera's own buildable packages, surfaced as `packages.<system>.*` and via the
# overlay. Empty until custom packages land — each will be a `callPackage` of a
# `pkgs/<name>/package.nix`.
{ pkgs }:
let
  inherit (pkgs) lib;
in
lib.filterAttrs (_: v: lib.isDerivation v) { }
