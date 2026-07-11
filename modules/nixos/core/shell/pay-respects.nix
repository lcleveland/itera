# itera shell battery — pay-respects, a shell command corrector.
#
# Installs pay-respects and binds an alias (default `f`) in zsh: run it right after
# a mistyped/failed command and it suggests the correction. (A modern, faster
# rewrite of the `thefuck` idea.)
#
# Opt-OUT (default ON); shell hook gated on the zsh battery.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool str;

  cfg = config.itera.shell.payRespects;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.payRespects = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install pay-respects to correct mistyped shell commands (type the alias after a failed command).";
    };

    alias = mkOption {
      type = str;
      default = "f";
      example = "fuck";
      description = "Shell alias used to invoke the command corrector.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.pay-respects ];

    programs.zsh.interactiveShellInit = mkIf zshEnabled ''
      eval "$(pay-respects zsh --alias ${cfg.alias})"
    '';
  };
}
