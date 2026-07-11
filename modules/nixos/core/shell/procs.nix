# itera shell battery — procs, a modern ps replacement.
#
# Installs procs and (opt-out) aliases ps to it. Alias only applies when the zsh
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

  cfg = config.itera.shell.procs;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.procs = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install procs, a modern ps replacement with colour and tree view.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias ps to procs.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.procs ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      ps = "procs";
    };
  };
}
