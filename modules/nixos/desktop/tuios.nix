# itera's terminal-workspace battery (tuios): a terminal window manager that
# tiles/floats persistent terminal sessions inside one TTY.
#
# This module is the SYSTEM half: it installs tuios and makes the terminal
# battery (WezTerm) open straight into it. `tuios attach` reattaches the most
# recent session (starting the daemon and restoring saved sessions if needed),
# or opens a new one when there is none. A plain shell is still
# `wezterm start -- nu`. The WezTerm settings are system-wide `mkDefault`s, so a
# user's `itera.users.<name>.programs.wezterm.settings` still wins per key.
#
# The HOME half, `modules/hjem/programs/tuios.nix`, writes each user's tuios
# config and, with Claude Code on, installs tuios's Claude integration.
#
# Sessions live in ~/.local/state, which impermanence already persists.
#
# Opt-OUT (default ON): set `itera.desktop.tuios.enable = false` to drop it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkPackageOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.tuios;
  claude = config.itera.ai.claude;

  # Claude Code agent teams, with each teammate in its own tuios pane: inside a
  # tuios pane (and not already under a tmux, real or the shim) `claude` runs
  # under tuios's tmux shim with agent teams on. Anywhere else it is unchanged.
  # Based on pkgs.claude-code, not claude.package, which this sets.
  claudeTeams =
    let
      real = lib.getExe pkgs.claude-code;
      wrapper = pkgs.writeShellScript "claude" ''
        if [ -n "''${TUIOS_PANE_ID:-}" ] && [ -z "''${TMUX:-}" ]; then
          exec ${lib.getExe cfg.package} tmux-shim -- env CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 ${real} "$@"
        fi
        exec ${real} "$@"
      '';
    in
    pkgs.symlinkJoin {
      # Same name as claude-code, so it reads as claude-code wherever it is listed.
      inherit (pkgs.claude-code) name;
      paths = [ pkgs.claude-code ];
      postBuild = "ln -sf ${wrapper} $out/bin/claude";
      meta.mainProgram = "claude";
    };
in
{
  options.itera.desktop.tuios = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install tuios, open WezTerm into it, and write each user's tuios config
        (plus its Claude Code integration when {option}`itera.ai.claude.enable`
        is set). On by default whenever {option}`itera.enable` is set.
      '';
    };

    package = mkPackageOption pkgs "tuios" { };
  };

  # Each integration below is gated on the battery it integrates with.
  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [
      cfg.package
      # Every tuios (daemon, client, hooks) must see socat: one without it calls
      # the socat hooks out of date and offers to swap in per-event ones.
      pkgs.socat
    ];

    itera = {
      # Claude integration (agent teams), only when the Claude battery is on.
      ai.claude.package = mkIf claude.enable (lib.mkOverride 900 claudeTeams);

      # DMS integration: the Inbox as a dank-bar widget (pkgs/dms-tuios-inbox).
      # The attribute name must match plugin.json's `id`.
      programs.dankMaterialShell.plugins.tuiosInbox = mkIf config.itera.desktop.dankMaterialShell.enable {
        src = mkDefault ../../../pkgs/dms-tuios-inbox;
        settings = mkDefault {
          tuios = lib.getExe cfg.package;
          notifySend = lib.getExe' pkgs.libnotify "notify-send";
          # The new-agent field starts Claude Code; hidden without it.
          agent = lib.optionalString claude.enable "claude";
        };
      };

      # WezTerm integration, only when the terminal battery ships WezTerm.
      programs.wezterm = mkIf config.itera.desktop.terminal.enable {
        settings = {
          default_prog = mkDefault [
            (lib.getExe cfg.package)
            "attach"
          ];
          # tuios reads key releases and unambiguous modifiers through the kitty
          # keyboard protocol (hold_window_mode needs it); WezTerm ships it off.
          enable_kitty_keyboard = mkDefault true;
          # tuios draws its own tabs/workspaces; WezTerm's bar only shows with 2+ tabs.
          hide_tab_bar_if_only_one_tab = mkDefault true;
        };
        # shortcut: while an overlay is open tuios asks for kitty "associated text",
        # and WezTerm then sends Escape, Enter and Backspace as ESC[27;1;27u, ESC[13;1;13u, ESC[127;1;127u.
        # tuios 0.12.1 named the key by that text (a raw control char), so `esc`
        # never matched (overlays wouldn't close) and Enter added a new line instead of
        # sending. Plain bytes parse fine. Drop this once tuios ignores control-char text.
        # A user who sets their own `extraLua` replaces this, so they must carry it.
        extraLua = ''
          config.keys = config.keys or {}
          table.insert(config.keys, { key = 'Escape', mods = 'NONE', action = wezterm.action.SendString '\x1b' })
          table.insert(config.keys, { key = 'Enter', mods = 'NONE', action = wezterm.action.SendString '\r' })
          table.insert(config.keys, { key = 'Backspace', mods = 'NONE', action = wezterm.action.SendString '\x7f' })
        '';
      };
    };
  };
}
