# itera shell battery — eza, a modern ls with colour, icons, and git status.
#
# Installs eza and (opt-out) aliases ls/ll/la/tree to it so it's used transparently
# in place of ls. Aliases only apply when the zsh battery is on.
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

  cfg = config.itera.shell.eza;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.eza = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install eza, a modern ls replacement with colour, icons, and git status.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias ls, ll, la, and tree to eza variants.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.eza ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      ls = "eza --icons";
      ll = "eza -lh --icons --git";
      la = "eza -lah --icons --git";
      tree = "eza --tree --icons";
    };
  };
}
