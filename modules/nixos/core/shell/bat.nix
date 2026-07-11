# itera shell battery — bat, a cat clone with syntax highlighting and paging.
#
# Installs bat and (opt-out) aliases cat to it. Also used as the fzf preview pager
# (see fzf.nix). Alias only applies when the zsh battery is on.
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

  cfg = config.itera.shell.bat;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.bat = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install bat, a cat clone with syntax highlighting and git integration.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias cat to bat.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.bat ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      cat = "bat";
    };
  };
}
