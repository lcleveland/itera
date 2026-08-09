# itera's Wayland↔X11 clipboard bridge battery.
#
# XWayland apps (Proton games, legacy X11 tools) live in their own X11 clipboard
# world: text copied in a Wayland app is not visible to them, and text copied
# inside them is not visible to Wayland apps. This battery bridges the two in BOTH
# directions so copy/paste works across the boundary, and — as a side effect —
# stops binary image data (screenshots) from being mangled into a garbled "Long
# Text" entry in the DankMaterialShell clipboard history.
#
# The bridge is load-bearing, not a belt-and-braces nicety: measured on mango rev
# 38fd988 with both daemons stopped, an X11 copy reached the Wayland clipboard 0/11
# times, and a Wayland copy reached X11 0/5 times. With them running, 5/5 both ways.
# mango does NOT sync the selections natively — do not "simplify" this away.
#
# It ships:
#   • wl-clipboard on PATH (wl-copy/wl-paste) for terminal clipboard access.
#   • The bridge daemons (below), as systemd *user* services.
#   • When Steam is on (itera.gaming), wl-clipboard-x11 + xdotool injected into
#     Steam's FHS container so Proton games can reach the clipboard atoms.
#
# The two directions:
#   • Wayland → X11: `wl-paste --watch` fires on each Wayland clipboard change and
#     mirrors text into the X11 CLIPBOARD (so a game can paste it).
#   • X11 → Wayland: `clipnotify` blocks on X11 CLIPBOARD/PRIMARY changes and
#     mirrors new text into the Wayland clipboard via `wl-copy` (so text copied in
#     a game lands in the Wayland/DMS clipboard).
# Each side compares against the other's current content before writing, which
# breaks the echo loop the two daemons would otherwise form.
#
# systemd targeting: the units bind to `graphical-session.target`. That target IS
# activated now — the mango autostart starts `mango-session.target`, which is bound
# to it (see `modules/hjem/programs/mango.nix`), so the older claim that nothing
# activates it no longer holds. The same autostart runs `systemctl --user
# import-environment DISPLAY WAYLAND_DISPLAY …`, so these units inherit an
# authoritative DISPLAY/WAYLAND_DISPLAY instead of guessing at the lowest-numbered
# socket in /tmp/.X11-unix — a guess that picks the wrong server whenever a stale
# socket outlives its session.
#
# `PartOf=` is the important half: it makes a session restart CYCLE these daemons.
# Without it, `itera-clipboard-x11-to-wayland` could never recover from an XWayland
# restart — `clipnotify` fast-fails ("Can't open X display", rc=1) once its X
# connection is gone, the loop's error branch swallowed that, and the unit spun at
# 1 Hz against a dead DISPLAY forever while systemd still reported it `active
# (running)`. `Restart=always` never fired because the script never exited. Observed
# live: its siblings logged 1–2 restarts across sessions while this unit logged 0,
# i.e. copy-out-of-XWayland silently stayed dead until the next reboot. The loop now
# exits on any non-timeout clipnotify failure so systemd can restart it with a fresh
# session environment.
#
# Every selection read is wrapped in `timeout`, because an X11 selection read blocks
# on the owning client answering: one hung Proton game — precisely the workload this
# battery exists for — would otherwise wedge a bridge permanently.
#
# The X11→Wayland loop also uses a bounded `clipnotify` wait rather than an
# unbounded one, so a missed edge (a selection change arriving while the loop was
# busy) self-heals on the next tick instead of persisting until the next copy. The
# reconcile body costs ~8 ms, so a 5 s tick is far cheaper than the 100 ms busy-poll
# this bridge originally replaced.
#
# autocutsel: it synchronises ONE selection against the X11 *cut buffer*, so a lone
# instance has nothing to link to. The old unconditional `-selection PRIMARY` unit
# therefore did nothing at all — measured live, PRIMARY did not track CLIPBOARD, and
# stopping it changed no clipboard behaviour, at a cost of ~17.5 s CPU per 5 h. It
# now runs only as the PAIR it has to be to work, and only when `selectToCopy` asks
# for it.
#
# Both watched directions are EVENT-DRIVEN (`wl-paste --watch` / `clipnotify`)
# rather than the original eiros bridge's 100 ms busy-poll, which spawned a
# `wl-paste` process ~10×/second forever just to detect changes. They use the exact
# same `wlr-data-control` / XFixes machinery a one-shot read already relied on, so
# they need nothing extra from mango. The text-only MIME filtering and the echo
# guard are preserved. As a bonus, --watch reports CLIPBOARD_STATE, so the bridge
# refuses to copy password-manager (sensitive) content into the persistent X11
# clipboard — a leak the blind poll could not have avoided.
#
# No system state to persist under impermanence — the clipboard is in-memory and
# per-user wl-clipboard/DMS state lives in $HOME (covered by home persistence),
# same as the other desktop batteries.
#
# Gated on `itera.enable && cfg.enable && itera.desktop.mango.enable`: on by default
# with the desktop (opt-out, like the editor/file-manager batteries), but inert on a
# headless host so the daemons never spin waiting for a compositor that never comes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.clipboard;

  # DISPLAY/WAYLAND_DISPLAY arrive from the session environment the mango autostart
  # imports, so there is nothing to discover. XWayland can still be a moment behind
  # the target on a cold start, so wait for its socket rather than failing the unit
  # straight into a restart loop.
  awaitX11Socket = ''
    : "''${DISPLAY:?DISPLAY unset — expected it from the mango session import-environment}"

    # ":0" and ":0.0" both denote /tmp/.X11-unix/X0.
    display_num=''${DISPLAY#:}
    display_num=''${display_num%%.*}
    x11_socket="/tmp/.X11-unix/X''${display_num}"

    for _ in $(seq 1 30); do
      [ -S "$x11_socket" ] && break
      sleep 1
    done
  '';

  awaitWaylandSocket = ''
    : "''${WAYLAND_DISPLAY:?WAYLAND_DISPLAY unset — expected it from the mango session import-environment}"
  '';

  # autocutsel synchronises ONE selection against the X11 cut buffer, so linking
  # PRIMARY to CLIPBOARD takes two instances with the cut buffer as the go-between.
  # `selection` is "CLIPBOARD" or "PRIMARY" (passed straight to -selection).
  autocutsel-wait =
    selection:
    pkgs.writeShellApplication {
      name = "itera-autocutsel-${lib.toLower selection}";
      runtimeInputs = with pkgs; [
        autocutsel
        coreutils
      ];
      text = ''
        ${awaitX11Socket}
        exec autocutsel -selection ${selection}
      '';
    };

  # Fired by `wl-paste --watch` each time the Wayland clipboard changes. Mirrors
  # ONLY text into the X11 CLIPBOARD.
  #
  # We deliberately ignore the content `wl-paste --watch` pipes on stdin and re-read
  # with an explicit type instead: without the type check, wl-paste requests
  # text/plain from a source that only offers image/png, the source blindly sends
  # binary, the shell strips NULs, and xclip re-advertises the corrupted bytes as
  # text — which the compositor bridges back as text/plain and DMS stores as a
  # "Long Text" clipboard entry.
  clipboard-sync-once = pkgs.writeShellApplication {
    name = "itera-clipboard-sync-once";
    runtimeInputs = with pkgs; [
      wl-clipboard
      xclip
      coreutils
      gnugrep
    ];
    text = ''
      # Never leak sensitive content into the persistent X11 CLIPBOARD/PRIMARY (and
      # thus the DMS clipboard history): a source marks it via the
      # x-kde-passwordManagerHint MIME type (password managers, browser password
      # fields), which wl-paste --watch surfaces as CLIPBOARD_STATE=sensitive. The
      # old eiros poll had no signal for this; --watch gives it to us for free.
      if [ "''${CLIPBOARD_STATE:-}" = "sensitive" ]; then
        exit 0
      fi

      offered_types=$(timeout 2 wl-paste --list-types 2>/dev/null) || exit 0

      # Only proceed if a text MIME type is on offer.
      printf '%s\n' "$offered_types" \
        | grep -iqE '^text/plain(;charset=.+)?$|^(UTF8_STRING|STRING|TEXT)$' || exit 0

      # Request the matched text type explicitly so wl-paste cannot fall back to
      # image/png when a source offers both. grep -im1 preserves the source's casing.
      req_type=$(printf '%s\n' "$offered_types" | grep -im1 '^text/plain') \
        || req_type=$(printf '%s\n' "$offered_types" | grep -Em1 '^(UTF8_STRING|STRING|TEXT)$') \
        || req_type=""

      current=$(timeout 2 wl-paste -n ''${req_type:+-t "$req_type"} 2>/dev/null) || exit 0
      [ -n "$current" ] || exit 0

      # Break the echo loop: if the X11 CLIPBOARD already holds this (our own prior
      # write, or content the X11→Wayland bridge just mirrored in), skip it. The
      # timeout matters — a hung X client never answers a selection request, and an
      # unbounded read here would wedge `wl-paste --watch` for the whole session.
      x11_current=$(timeout 2 xclip -selection clipboard -o 2>/dev/null) || true
      if [ "$current" = "$x11_current" ]; then
        exit 0
      fi

      printf '%s' "$current" | xclip -selection clipboard
    '';
  };

  # Watches the Wayland clipboard and mirrors text changes into X11 CLIPBOARD via
  # the helper above.
  wayland-to-x11-clipboard = pkgs.writeShellApplication {
    name = "itera-clipboard-wayland-to-x11";
    runtimeInputs = with pkgs; [
      wl-clipboard
      coreutils
      clipboard-sync-once
    ];
    text = ''
      ${awaitWaylandSocket}
      ${awaitX11Socket}

      # Event-driven: fires only when the Wayland clipboard changes.
      exec wl-paste --watch itera-clipboard-sync-once
    '';
  };

  # The reverse direction: blocks on X11 CLIPBOARD/PRIMARY changes (clipnotify
  # watches both and exits on either) and mirrors new text CLIPBOARD content into
  # the Wayland clipboard, so text copied inside a game is pasteable in Wayland apps.
  x11-to-wayland-clipboard = pkgs.writeShellApplication {
    name = "itera-clipboard-x11-to-wayland";
    runtimeInputs = with pkgs; [
      clipnotify
      xclip
      wl-clipboard
      coreutils
      gnugrep
    ];
    text = ''
      ${awaitWaylandSocket}
      ${awaitX11Socket}

      while true; do
        # Block until the X11 CLIPBOARD/PRIMARY changes, but not forever: the
        # bounded wait doubles as a reconcile tick, so a change that arrived while
        # this loop was busy is picked up on the next pass instead of being lost
        # until the user copies again.
        notify_rc=0
        timeout 5 clipnotify || notify_rc=$?
        case "$notify_rc" in
          0) ;; # a selection changed
          124)
            # Nothing changed within the window — usually just an idle clipboard,
            # so fall through and reconcile. But a server that hangs with its
            # socket still open makes clipnotify block rather than fail, which
            # looks identical from here; if the socket itself is gone, stop
            # pretending and let systemd restart us.
            [ -S "$x11_socket" ] || exit 1
            ;;
          *)
            # clipnotify fast-fails ("Can't open X display") once XWayland is gone.
            # Exit so systemd restarts us against the current session instead of
            # spinning at 1 Hz on a dead DISPLAY while looking healthy.
            exit 1
            ;;
        esac

        # Only mirror text: check the X11 target list before reading the content.
        # Every read is bounded — a hung selection owner never answers.
        targets=$(timeout 2 xclip -selection clipboard -o -t TARGETS 2>/dev/null) || continue
        printf '%s\n' "$targets" \
          | grep -iqE '^(UTF8_STRING|STRING|TEXT)$|^text/plain' || continue

        current=$(timeout 2 xclip -selection clipboard -o 2>/dev/null) || continue
        [ -n "$current" ] || continue

        # Break the echo loop: skip if the Wayland clipboard already holds this
        # (our own prior push, or content the Wayland→X11 bridge just mirrored out).
        wl_current=$(timeout 2 wl-paste -n 2>/dev/null) || true
        if [ "$current" = "$wl_current" ]; then
          continue
        fi

        printf '%s' "$current" | wl-copy
      done
    '';
  };

  # Shared unit shape for the user services. Bound to the graphical session so they
  # start with it and — crucially — are stopped and restarted with it, rather than
  # outliving a dead X server the way the old default.target daemons did.
  bridgeService = description: exec: {
    inherit description;
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    # XWayland may not be serving yet on a cold start, and the X11→Wayland loop now
    # deliberately exits when its display goes away. Neither should trip systemd's
    # start rate limit; PartOf= still bounds the retries to the session's lifetime.
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = exec;
      # `always`, not `on-failure`: `wl-paste --watch` exits 0 when the compositor
      # goes away, and we want the bridge back as soon as it returns.
      Restart = "always";
      RestartSec = 1;
    };
  };
in
{
  options.itera.desktop.clipboard = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Run the Wayland↔X11 clipboard bridge so copy/paste works in both directions
        between Wayland apps and XWayland apps (Proton games, legacy X11 tools),
        install {command}`wl-clipboard`, and — when {option}`itera.gaming` is on —
        inject the clipboard tools into Steam's container. Also stops binary image
        data from showing up as garbled "Long Text" in the DankMaterialShell
        clipboard history. On by default whenever the mango desktop is enabled; set
        to `false` to opt out. Inert on a headless host (no compositor).

        mango does not sync the two selections itself, so turning this off leaves
        copy/paste across the XWayland boundary broken in both directions.
      '';
    };

    selectToCopy = mkOption {
      type = bool;
      default = false;
      description = ''
        Link the X11 PRIMARY selection (highlighted text) and CLIPBOARD together for
        XWayland apps, so selecting text copies it. Off by default; the two bridge
        services run regardless of this toggle. Runs a pair of {command}`autocutsel`
        instances — the tool bridges a single selection against the X11 cut buffer,
        so both are required for the link to exist at all.
      '';
    };

    steamIntegration = mkOption {
      type = bool;
      default = true;
      description = ''
        Inject {command}`wl-clipboard-x11` and {command}`xdotool` into Steam's FHS
        container so Proton games can reach the clipboard atoms. Only takes effect
        when Steam is enabled (via {option}`itera.gaming`); a no-op otherwise.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable && config.itera.desktop.mango.enable) (mkMerge [
    {
      # wl-copy/wl-paste on PATH for terminal clipboard access.
      environment.systemPackages = [ pkgs.wl-clipboard ];

      systemd.user.services = {
        itera-clipboard-wayland-to-x11 = bridgeService "Mirror Wayland clipboard text into the X11 CLIPBOARD for XWayland apps" "${wayland-to-x11-clipboard}/bin/itera-clipboard-wayland-to-x11";

        itera-clipboard-x11-to-wayland = bridgeService "Mirror X11 CLIPBOARD text into the Wayland clipboard (copy out of XWayland apps)" "${x11-to-wayland-clipboard}/bin/itera-clipboard-x11-to-wayland";
      };
    }

    (mkIf cfg.selectToCopy {
      systemd.user.services = {
        itera-clipboard-autocutsel-clipboard = bridgeService "Sync the X11 CLIPBOARD selection with the cut buffer (select-to-copy, half 1 of 2)" "${autocutsel-wait "CLIPBOARD"}/bin/itera-autocutsel-clipboard";

        itera-clipboard-autocutsel-primary = bridgeService "Sync the X11 PRIMARY selection with the cut buffer (select-to-copy, half 2 of 2)" "${autocutsel-wait "PRIMARY"}/bin/itera-autocutsel-primary";
      };
    })

    (mkIf (cfg.steamIntegration && config.programs.steam.enable) {
      programs.steam.extraPackages = with pkgs; [
        wl-clipboard-x11
        xdotool
      ];
    })
  ]);
}
