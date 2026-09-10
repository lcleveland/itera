# itera's own buildable packages, surfaced as `packages.<system>.*` and via the
# overlay (overlays/default.nix, as `pkgs.itera.*`). Each entry is a
# `callPackage` of a `pkgs/<name>/package.nix`; none yet.
#
# NOTE: not everything under `pkgs/` is a package. `pkgs/dms-screencast-chooser/`
# and `pkgs/dms-itera-update/` are source-only — DankMaterialShell plugins (QML +
# plugin.json) that `modules/nixos/desktop/screencast.nix` and
# `modules/nixos/desktop/update-indicator.nix` register by PATH, not by building
# them — so they have no `package.nix` and deliberately do not appear here.
{ pkgs }:
let
  inherit (pkgs) lib;
in
lib.filterAttrs (_: lib.isDerivation) { }
