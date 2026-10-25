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

  # ponytail: open-webui 0.12.3 imports mcp 1.x names that mcp 2 removed and dies
  # at startup. The patch is upstream 0.12.4's port of utils/mcp/client.py to
  # mcp 2; drop once nixpkgs ships open-webui 0.12.4 or later.
  open-webui = prev.open-webui.overridePythonAttrs (o: {
    patches = (o.patches or [ ]) ++ [ ./open-webui-mcp2.patch ];
  });

  # ponytail: nixpkgs marks posthog (pulled in by open-webui) broken since mcp 2;
  # only its MCP integration fails, which open-webui never imports. Drop once
  # nixpkgs PR 578265 lands.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pyPrev: {
      posthog = pyPrev.posthog.overridePythonAttrs (o: {
        disabledTestPaths = (o.disabledTestPaths or [ ]) ++ [ "posthog/test/mcp" ];
        meta = o.meta // {
          broken = false;
        };
      });
    })
  ];
}
