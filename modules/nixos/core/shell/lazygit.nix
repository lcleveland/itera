# itera shell battery — lazygit, a terminal UI for git.
#
# Installs lazygit and (opt-out) aliases lg to it. Alias only applies when the zsh
# battery is on.
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

  cfg = config.itera.shell.lazygit;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.lazygit = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install lazygit, a fast terminal UI for git.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias lg to lazygit.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.lazygit ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      lg = "lazygit";
    };
  };
}
