# itera's command-line battery: the `itera` control command.
#
# Puts the `itera` command (cli/itera.sh, packaged as `itera-consumer` in
# flake/cli.nix) on every user's PATH, so anyone importing itera can drive
# itera-related actions on their own system:
#
#   itera facter report [path]   regenerate a hardware report + tuning summary
#   itera rebuild [args]         rebuild from your flake (nh os switch)
#   itera update [args]          update flake inputs, then rebuild
#   itera gc [args]              prune old generations (nh clean all)
#
# rebuild/update/gc are thin `nh` wrappers that act on the consumer's OWN flake
# (via {option}`itera.nix.nh.flake` / NH_FLAKE), not itera's — the itera-repo
# `testhost` verbs are deliberately NOT in this build (see flake/cli.nix).
#
# Tab-completion for the command is shipped per-user by the companion home
# battery `itera.programs.itera` (modules/hjem/programs/itera.nix).
#
# Opt-OUT (default ON with `itera.enable`), following the core-battery shape. The
# dev test hosts set `itera.cli.enable = false` and install the full `itera`
# (with `testhost`) via dev/remote-access.nix instead.
{
  config,
  lib,
  pkgs,
  iteraInputs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool;

  cfg = config.itera.cli;
in
{
  options.itera.cli.enable = mkOption {
    type = bool;
    default = true;
    description = ''
      Install the `itera` command — a single entry point for itera-related
      actions on this system (`itera facter report`, `itera rebuild`,
      `itera update`, `itera gc`). On by default whenever {option}`itera.enable`
      is set; set to `false` to omit it.
    '';
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [
      iteraInputs.self.packages.${pkgs.stdenv.hostPlatform.system}.itera-consumer
    ];
  };
}
