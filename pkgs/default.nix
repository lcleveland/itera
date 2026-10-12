# itera's own buildable packages, surfaced as `packages.<system>.*` and via the
# overlay (overlays/default.nix, as `pkgs.itera.*`). Each entry is a
# `callPackage` of a `pkgs/<name>/package.nix`.
#
# NOTE: not everything under `pkgs/` is a package. `pkgs/dms-screencast-chooser/`,
# `pkgs/dms-itera-update/` and `pkgs/dms-layout-chooser/` are source-only —
# DankMaterialShell plugins (QML + plugin.json) that
# `modules/nixos/desktop/screencast.nix`, `modules/nixos/desktop/update-indicator.nix`
# and `modules/nixos/desktop/dankmaterialshell.nix` register by PATH, not by
# building them — so they have no `package.nix` and deliberately do not appear here.
{ pkgs }:
let
  inherit (pkgs) lib;
in
lib.filterAttrs (_: lib.isDerivation) {
  itera-mono = pkgs.callPackage ./itera-mono/package.nix { };
}
