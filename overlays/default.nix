# itera's package overlay. Exposes itera's own packages under `pkgs.itera.*`
# and is the place for any package overrides the curated experience needs.
# Passthrough while `pkgs/default.nix` has no packages in it — see the note there
# on why `pkgs/dms-screencast-chooser/` does not count.
_inputs: _final: _prev: {
  itera = { };
}
