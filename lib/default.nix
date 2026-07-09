{ lib }:
{
  # Module discovery helpers (auto-import). Grows over time with generators,
  # custom types, etc. as the curated layer fills in.
  modules = import ./modules.nix { inherit lib; };
}
