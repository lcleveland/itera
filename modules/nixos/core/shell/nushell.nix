# itera's shell battery — core nushell module (system layer).
#
# itera shipped no shell config after the zsh battery was removed (#39), falling
# back to NixOS's implicit bash. This battery makes nushell the default login
# shell system-wide and installs carapace, the multi-shell completion engine.
#
# Why carapace: nushell natively completes its own builtins/subcommands/flags,
# file paths, variables, and `extern`-declared signatures — but it ships NO
# completions for external commands (git, docker, systemctl, …). carapace fills
# exactly that gap (1000+ command specs) and is wired in as nushell's external
# completer by the companion home battery. Native + carapace compose: nushell
# only calls the external completer when the command head isn't a nushell command.
#
# Layer split: nushell as a login shell is a SYSTEM concern (this file installs
# the package, registers it in /etc/shells, and sets users.defaultUserShell). The
# per-user interactive config (config.nu / env.nu + the carapace hookup) lives in
# the home layer at `modules/hjem/programs/nushell.nix`, since — unlike zsh —
# NixOS has no `programs.nushell` module and nushell reads its config from
# ~/.config/nushell, not /etc.
#
# Opt-OUT (default ON): set `itera.shell.nushell.enable = false` to drop it. Keep
# nushell but restore bash as the login shell with
# `itera.shell.nushell.defaultShell.enable = false`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption mkPackageOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool;

  cfg = config.itera.shell.nushell;
in
{
  options.itera.shell.nushell = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install nushell system-wide and make it the default login shell (plus
        carapace for external-command completion). On by default whenever
        {option}`itera.enable` is set; set to `false` to opt out.
      '';
    };

    package = mkPackageOption pkgs "nushell" { };

    defaultShell.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Set nushell as the default login shell for all users
        ({option}`users.defaultUserShell`). Disable to keep nushell installed and
        configured while leaving the login shell as bash.
      '';
    };

    carapace = {
      enable = mkEnableOption "carapace, the multi-shell command-completion engine" // {
        default = true;
      };

      package = mkPackageOption pkgs "carapace" { };
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optional cfg.carapace.enable cfg.carapace.package;

    # Register nushell's `nu` (its package sets `shellPath = "/bin/nu"`) in
    # /etc/shells so it is a valid login shell for chsh and PAM.
    environment.shells = [ cfg.package ];

    # Normal priority (not mkDefault): NixOS's bash module already sets this at
    # mkDefault, so a tie would conflict. Normal priority wins over that; consumers
    # who want a different login shell use `defaultShell.enable = false` or mkForce.
    users.defaultUserShell = mkIf cfg.defaultShell.enable cfg.package;
  };
}
