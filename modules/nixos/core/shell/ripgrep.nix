# itera shell battery — ripgrep, a fast recursive grep.
#
# Installs ripgrep and (opt-out) aliases grep to `rg`. Note rg's argument semantics
# differ from GNU grep, so this alias is opt-out on its own toggle. Alias only
# applies when the zsh battery is on.
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

  cfg = config.itera.shell.ripgrep;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.ripgrep = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install ripgrep, a fast recursive search tool.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias grep to rg (note: rg's flags differ from GNU grep).";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.ripgrep ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      grep = "rg";
    };
  };
}
