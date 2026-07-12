# itera shell battery — atuin, enhanced shell history.
#
# Installs atuin and hooks it into zsh, replacing the default history search
# (Ctrl+R / up-arrow) with a searchable, syncable SQLite-backed history. Encrypted
# cross-device sync is available but OFF by default (opt-in per host/user). The
# per-user history database lives under $HOME and is covered by itera's home
# persistence.
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
  inherit (lib.types) bool enum;

  cfg = config.itera.shell.atuin;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.atuin = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install atuin for enhanced shell history with fuzzy search (replaces Ctrl+R).";
    };

    shellIntegration.enable = mkOption {
      type = bool;
      default = true;
      description = "Add atuin shell integration to zsh (hooks Ctrl+R and up-arrow history search).";
    };

    filterMode = mkOption {
      type = enum [
        "global"
        "session"
        "directory"
        "host"
      ];
      default = "global";
      description = "History filter mode: global (all sessions), session, directory, or host.";
    };

    sync.enable = mkOption {
      type = bool;
      default = false;
      description = "Enable the atuin sync daemon for encrypted cross-device history synchronisation.";
    };

    enterAccept = mkOption {
      type = bool;
      default = false;
      description = ''
        Run the selected command immediately when pressing Enter in the atuin
        search UI. Off by default: with enter_accept on, atuin's zsh integration
        swallows the first Enter presses on a freshly opened terminal (notably
        under Ghostty's kitty keyboard protocol), leaving a blinking caret until
        you press Enter several times.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.atuin ];

    # atuin only reads $ATUIN_CONFIG_DIR/config.toml (default ~/.config/atuin), so
    # without this the /etc/atuin/config.toml below is silently ignored. Landing it
    # in /etc/set-environment (sourced by /etc/zshenv) makes it visible before
    # `atuin init zsh` runs in interactiveShellInit.
    environment.variables.ATUIN_CONFIG_DIR = "/etc/atuin";

    environment.etc."atuin/config.toml".text = ''
      filter_mode = "${cfg.filterMode}"
      sync_frequency = "${if cfg.sync.enable then "10m" else "0"}"
      enter_accept = ${lib.boolToString cfg.enterAccept}
    '';

    programs.zsh.interactiveShellInit = mkIf (cfg.shellIntegration.enable && zshEnabled) ''
      eval "$(atuin init zsh)"
    '';
  };
}
