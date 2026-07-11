# itera shell battery — Zellij terminal multiplexer.
#
# Installs Zellij with optional shell auto-attach. Unlike the rest of the shell
# stack this defaults OFF (a multiplexer is a strong workflow opinion), matching
# eiros. Enable it, and optionally have zsh auto-attach a session on launch.
#
# Opt-IN (default OFF); auto-attach hook gated on the zsh battery.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool;

  cfg = config.itera.shell.zellij;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.zellij = {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Install the Zellij terminal multiplexer.";
    };

    autoAttach.enable = mkOption {
      type = bool;
      default = false;
      description = "Automatically attach to (or create) a Zellij session when opening a terminal.";
    };

    autoExit.enable = mkOption {
      type = bool;
      default = false;
      description = "Exit the shell when detaching from a Zellij session (only applies when autoAttach is enabled).";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.zellij ];

    programs.zsh.interactiveShellInit = mkIf (cfg.autoAttach.enable && zshEnabled) ''
      if [[ -z "$ZELLIJ" ]]; then
        if zellij list-sessions 2>/dev/null | grep -q .; then
          zellij attach
        else
          zellij
        fi
        ${lib.optionalString cfg.autoExit.enable "exit"}
      fi
    '';
  };
}
