# itera shell battery — zoxide, a smarter cd that tracks frecency.
#
# Installs zoxide and hooks it into zsh, adding `z <dir>` / `zi` for jumping to
# frequently-used directories. Optionally replaces `cd` itself.
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
  inherit (lib.types) bool;

  cfg = config.itera.shell.zoxide;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.zoxide = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install zoxide, a smarter cd that tracks frecency and jumps with z/zi.";
    };

    shellIntegration.enable = mkOption {
      type = bool;
      default = true;
      description = "Add zoxide shell integration to zsh (enables z, zi, and optionally replaces cd).";
    };

    replaceCd.enable = mkOption {
      type = bool;
      default = false;
      description = "Replace the cd command with zoxide (sets --cmd cd in init).";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.zoxide ];

    programs.zsh.interactiveShellInit = mkIf (cfg.shellIntegration.enable && zshEnabled) ''
      eval "$(zoxide init zsh${lib.optionalString cfg.replaceCd.enable " --cmd cd"})"
    '';
  };
}
