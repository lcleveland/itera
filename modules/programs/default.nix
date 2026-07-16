# Registry of itera's curated programs.
#
# Each sibling file (auto-discovered, `_`-prefixed skipped) is a registration
# record: `{ lib, iteraLib }: iteraLib.programs.mkCuratedProgram { … }`, returning
# `{ systemModule, usersSubmodule }`.
#
# NOT a NixOS module and NOT auto-imported by the `modules/nixos` / `modules/hjem`
# scanners (they only scan their own trees). It is imported explicitly:
#   - `modules/nixos/default.nix` splices in each `.systemModule` (the system-wide
#     `itera.programs.<app>` defaults), and
#   - `modules/nixos/core/users.nix` splices each `.usersSubmodule` into the
#     `itera.users.<name>` submodule (the per-user `programs.<app>` overrides).
{ lib, iteraLib }:
map (path: import path { inherit lib iteraLib; }) (iteraLib.modules.listNixModules ./.)
