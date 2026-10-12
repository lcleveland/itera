# itera's package overlay. Exposes itera's own packages (pkgs/default.nix)
# under `pkgs.itera.*` and is the place for any package overrides the curated
# experience needs.
_inputs: final: _prev: {
  itera = import ../pkgs { pkgs = final; };
}
