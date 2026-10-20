# itera's package overlay. Exposes itera's own packages (pkgs/default.nix)
# under `pkgs.itera.*` and is the place for any package overrides the curated
# experience needs.
_inputs: final: prev:
let
  # buildFHSEnv defaults to bwrap `--die-with-parent`, so an FHS app (OnlyOffice,
  # Steam, AppImages…) dies with whatever spawned it. Nemo launches opened files
  # as its own children, so closing Nemo closed the document. Flip the default
  # only; a package that sets `dieWithParent` itself keeps its value. `args` may
  # be a fixed-point function (`finalAttrs: { … }`, e.g. caido-desktop).
  keepFHSAppsAlive =
    build: args:
    build (
      if prev.lib.isFunction args then
        finalAttrs: { dieWithParent = false; } // args finalAttrs
      else
        { dieWithParent = false; } // args
    );
in
{
  itera = import ../pkgs { pkgs = final; };

  buildFHSEnv = keepFHSAppsAlive prev.buildFHSEnv;
  buildFHSEnvBubblewrap = keepFHSAppsAlive prev.buildFHSEnvBubblewrap;

  # ponytail: khal (pulled in by DMS's calendar) now builds with structuredAttrs,
  # where sphinx-hook.sh's `eval "(…($sphinxBuilders))"` sees only the list's first
  # element, so the man builder never runs and the `man` output is missing. A
  # space-separated string survives the hook; drop once the hook reads arrays.
  khal = prev.khal.overrideAttrs { sphinxBuilders = "html man"; };

  # ponytail: same structuredAttrs fallout — open-webui passes makeWrapperArgs as
  # one "--set NAME VALUE" string, which arrives as a single argv element and
  # makeWrapper dies on it. Split into separate args; drop once nixpkgs does.
  open-webui = prev.open-webui.overridePythonAttrs (o: {
    makeWrapperArgs = prev.lib.concatMap (prev.lib.splitString " ") o.makeWrapperArgs;
  });
}
