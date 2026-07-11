# itera shell battery — gping, ping with a live graph.
#
# Installs gping and (opt-out) aliases ping to it. Alias only applies when the zsh
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

  cfg = config.itera.shell.gping;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.gping = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install gping, ping with a live latency graph.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias ping to gping.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.gping ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      ping = "gping";
    };
  };
}
