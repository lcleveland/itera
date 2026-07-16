# Evaluation check for the cli battery (modules/nixos/core/cli.nix): the
# consumer `itera` command.
#
# The battery just puts the `itera-consumer` package on PATH, gated on
# itera.enable + itera.cli.enable. We assert the default-on wiring and that the
# toggle removes it. `mkConfig` builds on self.nixosModules.default exactly as a
# consumer would, so the `iteraInputs.self.packages.<system>.itera-consumer`
# reference is exercised for real.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;

  iteraCmd = self.packages.${pkgs.stdenv.hostPlatform.system}.itera-consumer;

  base = mkConfig [ ];
  cliOff = mkConfig [ { itera.cli.enable = false; } ];

  hasItera = cfg: builtins.elem iteraCmd cfg.environment.systemPackages;

  # A consumer with a user: the home battery (modules/hjem/programs/itera.nix)
  # should ship the completion spec to that user (carapace on by default).
  specPath = "carapace/specs/itera.yaml";
  withUser = mkConfig [ { itera.users.alice.initialPassword = "changeme"; } ];
  noCarapace = mkConfig [
    {
      itera.users.alice.initialPassword = "changeme";
      itera.shell.nushell.carapace.enable = false;
    }
  ];
  userSpec = withUser.hjem.users.alice.xdg.config.files.${specPath};
  specText = builtins.readFile userSpec.source;

  checks = {
    # ── system battery ───────────────────────────────────────────────────
    "itera.cli is enabled by default" = base.itera.cli.enable;
    "the itera command is installed by default" = hasItera base;
    "itera.cli.enable = false removes the itera command" = !(hasItera cliOff);

    # ── home battery (completion for all users) ──────────────────────────
    "completion spec shipped to the user by default" =
      withUser.hjem.users.alice.xdg.config.files ? ${specPath};
    "shipped spec is the consumer spec (has the consumer verbs)" =
      lib.hasInfix "name: rebuild" specText && lib.hasInfix "name: gc" specText;
    "shipped spec omits the dev-only testhost verbs" = !(lib.hasInfix "name: testhost" specText);
    "no completion spec when carapace is off" =
      !(noCarapace.hjem.users.alice.xdg.config.files ? ${specPath});
  };
in
mkCheckDrv "itera-cli-eval" checks
