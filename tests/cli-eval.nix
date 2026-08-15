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
  # Both specs come from one source (cli/carapace-spec.nix), rendered to YAML by
  # whoever installs them. Assert against that DATA rather than the rendered file:
  # it is what the two builds actually differ in, and reading the generated file
  # back would mean an import-from-derivation in every eval.
  mkSpec = withTesthost: import ../cli/carapace-spec.nix { inherit lib withTesthost; };
  verbs = spec: map (c: c.name) spec.commands;
  consumerVerbs = verbs (mkSpec false);
  fullVerbs = verbs (mkSpec true);

  checks = {
    # ── system battery ───────────────────────────────────────────────────
    "itera.cli is enabled by default" = base.itera.cli.enable;
    "the itera command is installed by default" = hasItera base;
    "itera.cli.enable = false removes the itera command" = !(hasItera cliOff);

    # ── home battery (completion for all users) ──────────────────────────
    "completion spec shipped to the user by default" =
      withUser.hjem.users.alice.xdg.config.files ? ${specPath};
    "no completion spec when carapace is off" =
      !(noCarapace.hjem.users.alice.xdg.config.files ? ${specPath});

    # ── the shared carapace spec ─────────────────────────────────────────
    "consumer spec carries the consumer verbs" = lib.all (v: builtins.elem v consumerVerbs) [
      "facter"
      "rebuild"
      "update"
      "boot"
      "update-boot"
      "gc"
      "disks"
      "firmware"
      "help"
    ];
    "consumer spec omits the dev-only testhost verbs" = !(builtins.elem "testhost" consumerVerbs);
    "full spec adds testhost and nothing else" =
      builtins.elem "testhost" fullVerbs
      && lib.sort (a: b: a < b) (lib.remove "testhost" fullVerbs) == lib.sort (a: b: a < b) consumerVerbs;
  };
in
mkCheckDrv "itera-cli-eval" checks
