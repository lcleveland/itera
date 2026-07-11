# itera shell battery — duf, a modern df replacement.
#
# Installs duf and (opt-out) aliases df to it. Alias only applies when the zsh
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

  cfg = config.itera.shell.duf;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.duf = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install duf, a modern df replacement with a clearer disk-usage table.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias df to duf.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.duf ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      df = "duf";
    };
  };
}
