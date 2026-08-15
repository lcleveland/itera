# itera's own buildable packages, surfaced as `packages.<system>.*` and via the
# overlay (overlays/default.nix, as `pkgs.itera.*`). Each entry is a
# `callPackage` of a `pkgs/<name>/package.nix`; none yet.
#
# NOTE: not everything under `pkgs/` is a package. `pkgs/dms-screencast-chooser/`
# is source-only — a DankMaterialShell plugin (QML + plugin.json) that
# `modules/nixos/desktop/screencast.nix` registers by PATH, not by building it —
# so it has no `package.nix` and deliberately does not appear here.
{ pkgs }:
let
  inherit (pkgs) lib;
in
lib.filterAttrs (_: lib.isDerivation) { }
