# itera's tuios user config (home layer of `itera.desktop.tuios`).
#
# tuios settings go in config.d/, not config.toml: tuios rewrites config.toml
# from its settings page, and config.d files are merged under it (config.toml
# wins, so a key here must not also be set there).
#
# With Claude Code on (`itera.ai.claude.enable`), a login-time user service runs
# `tuios integration install claude-code --statusline`: it merges tuios's
# agent-state hooks and status line into ~/.claude/settings.json and writes the
# tuios skill; Claude's permission prompts that fit on one line are then held for
# the tuios Inbox (`[agents.approvals]`). The install can't be an hjem file, since
# Claude Code rewrites settings.json itself; reinstalling an integration that is
# already current changes nothing.
{
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit (lib.modules) mkIf mkMerge;

  enable = (osConfig.itera.enable or false) && (osConfig.itera.desktop.tuios.enable or false);
  # Integrations, each gated on the battery it integrates with.
  claude = osConfig.itera.ai.claude.enable or false;
  dms = osConfig.itera.desktop.dankMaterialShell.enable or false;
  tuios = lib.getExe osConfig.itera.desktop.tuios.package;
  jq = lib.getExe pkgs.jq;

  # Run by tuios's Claude status line feed (--then) with Claude's status JSON on
  # stdin. tuios's own context value ("13%") isn't a number its colour rules can
  # compare, so this files the percent under one of three keys, each with a fixed
  # colour on the rail. It prints nothing, so Claude's status line stays empty.
  contextLevel = pkgs.writeShellScript "tuios-context-level" ''
    pct=$(${jq} -r '.context_window.used_percentage // empty | floor' 2>/dev/null) || exit 0
    [ -n "$pct" ] || exit 0
    ok= warn= high=
    if [ "$pct" -ge 80 ]; then high="ctx $pct%"; elif [ "$pct" -ge 50 ]; then warn="ctx $pct%"; else ok="ctx $pct%"; fi
    ${tuios} set-agent-meta "ctx_ok=$ok" "ctx_warn=$warn" "ctx_high=$high" >/dev/null 2>&1
    exit 0
  '';

  # Claude's own "waiting for your input" alert is an OSC 777 that tuios hands to
  # WezTerm, which posts it critical with no timeout, so it never closes. tuios
  # already alerts on needs_input from the hooks, so turn Claude's off.
  quietClaude = pkgs.writeShellScript "claude-notifications-off" ''
    f="$HOME/.claude.json"
    [ -f "$f" ] || exit 0
    t=$(mktemp) || exit 0
    # Written in place, not moved: the file is an impermanence bind mount.
    ${jq} '.preferredNotifChannel = "notifications_disabled"' "$f" > "$t" && cat "$t" > "$f"
    rm -f "$t"
  '';

  settings = {
    startup = {
      # Both default true, but read as false when the config has no [startup]
      # table; set here so config.toml (tuios-written) needn't carry them.
      daemon = true; # bare `tuios` attaches to a daemon session
      tiled = true; # new sessions start tiled
      open_default_window = true; # an empty session starts with a terminal
      start_in_terminal_mode = true; # typing goes to the pane, not window mode
    };
    # Never run a project's tape just because a shell entered its directory.
    tape.autorun = "off";
    # Sessions persist (~/.local/state), so resume each pane's agent after a
    # daemon restart instead of asking per pane.
    daemon.resume_agents = "auto";
  }
  // lib.optionalAttrs dms {
    # Agent alerts as desktop popups that time out. tuios's own popup goes via
    # WezTerm, which sends it critical with timeout 0, so DMS keeps it up forever.
    # The daemon runs `command` with sh and TUIOS_* in the env; it reads it at start.
    notifications.agent = {
      notify = false;
      command = ''${lib.getExe pkgs.libnotify} -a tuios -u normal -t 8000 "$TUIOS_WINDOW_NAME: $TUIOS_AGENT_STATE" "$TUIOS_AGENT_MESSAGE"'';
    };
  }
  // lib.optionalAttrs claude {
    # Answer short Claude permission prompts from the Inbox (prefix+i): 1 once, 2 always, 3 deny.
    agents.approvals = {
      enabled = [ "claude-code" ];
      hold_seconds = 120;
    };
    # The shipped rail row, with cost and the always-on context level in place
    # of `context` (which only draws at 80% and over). harness and model are
    # dropped: they read "claude · Opus" on every row, and the row never wraps
    # (a token that doesn't fit is dropped whole), so they crowded out cost,
    # context and the message.
    appearance.sidebar.agent_row = {
      tokens = [
        "session"
        "need"
        "name"
        "progress"
        "elapsed"
        "$cost"
        "$ctx_ok"
        "$ctx_warn"
        "$ctx_high"
        "subagents"
        "pr"
        "meta"
        "now"
        "message"
      ];
      "$ctx_ok".fg = "success";
      "$ctx_warn".fg = "warning";
      "$ctx_high".fg = "error";
    };
    # Keep finished agents' full rows (cost, context, last message) instead of
    # folding them to one line after an hour at rest.
    appearance.sidebar.agent_rest_fold = "off";
  };
in
{
  config = mkIf enable (mkMerge [
    {
      xdg.config.files."tuios/config.d/nixos.toml" = {
        source = (pkgs.formats.toml { }).generate "tuios-nixos.toml" settings;
        clobber = true;
      };
    }

    (mkIf claude {
      systemd.services.tuios-claude-integration = {
        description = "Install tuios hooks, status line and skill into Claude Code";
        wantedBy = [ "default.target" ];
        # With socat and sh on PATH tuios writes hooks that hand each event to the
        # daemon through socat; without either, hooks that start a tuios process
        # per event. A user unit's PATH has no sh, so both are listed.
        path = [
          pkgs.socat
          pkgs.bash
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${tuios} integration install claude-code --statusline --then ${contextLevel}";
          ExecStartPost = "${quietClaude}";
        };
      };
    })
  ]);
}
