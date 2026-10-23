# Registry of itera's curated programs.
#
# Each sibling file (auto-discovered, `_`-prefixed skipped) is a registration
# record: `{ lib, iteraLib }: iteraLib.programs.mkCuratedProgram { … }`, returning
# `{ name, systemModule, usersSubmodule, resolve }`. The registry is keyed by
# that name.
#
# NOT a NixOS module and NOT auto-imported by the `modules/nixos` / `modules/hjem`
# scanners (they only scan their own trees). It is imported explicitly:
#   - `modules/nixos/default.nix` splices in each `.systemModule` (the system-wide
#     `itera.programs.<app>` defaults),
#   - `modules/nixos/core/users.nix` splices each `.usersSubmodule` into the
#     `itera.users.<name>` submodule (the per-user `programs.<app>` overrides), and
#   - `modules/nixos/default.nix` and `modules/hjem/default.nix` pass it as the
#     `programs` module arg, so renderers call `programs.<app>.resolve osConfig name`.
{ lib, iteraLib }:
lib.listToAttrs (
  map (
    path:
    let
      r = import path { inherit lib iteraLib; };
    in
    lib.nameValuePair r.name r
  ) (iteraLib.modules.listNixModules ./.)
)
