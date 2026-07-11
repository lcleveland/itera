# itera shell battery — fd, a fast and user-friendly find.
#
# Installs fd and (opt-out) aliases find to it. Also backs the default fzf file
# command (see fzf.nix). fd's argument semantics differ from GNU find, so the alias
# is opt-out on its own toggle. Alias only applies when the zsh battery is on.
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

  cfg = config.itera.shell.fd;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.fd = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install fd, a fast and user-friendly find replacement.";
    };

    aliases.enable = mkOption {
      type = bool;
      default = true;
      description = "Alias find to fd (note: fd's flags differ from GNU find).";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.fd ];

    programs.zsh.shellAliases = mkIf (cfg.aliases.enable && zshEnabled) {
      find = "fd";
    };
  };
}
