# itera's Wayland↔X11 clipboard bridge battery.
#
# XWayland apps (Proton games, legacy X11 tools) live in their own X11 clipboard
# world: text copied in a Wayland app is not visible to them, and text copied
# inside them is not visible to Wayland apps. This battery bridges the two in BOTH
# directions so copy/paste works across the boundary, and — as a side effect —
# stops binary image data (screenshots) from being mangled into a garbled "Long
# Text" entry in the DankMaterialShell clipboard history.
#
# It ships:
#   • wl-clipboard on PATH (wl-copy/wl-paste) for terminal clipboard access.
#   • The bridge daemons (below), as systemd *user* services.
#   • When Steam is on (itera.gaming), wl-clipboard-x11 + xdotool injected into
#     Steam's FHS container so Proton games can reach the clipboard atoms.
#
# The two directions:
#   • Wayland → X11: `wl-paste --watch` fires on each Wayland clipboard change and
#     mirrors text into the X11 CLIPBOARD (so a game can paste it). autocutsel then
#     keeps the X11 CLIPBOARD/PRIMARY selections in step.
#   • X11 → Wayland: `clipnotify` blocks on X11 CLIPBOARD/PRIMARY changes and
#     mirrors new text into the Wayland clipboard via `wl-copy` (so text copied in
#     a game lands in the Wayland/DMS clipboard). MangoWC's XWayland does not do
#     this sync itself, so without this daemon copy-OUT-of-a-game silently fails.
# Each side compares against the other's current content before writing, which
# breaks the echo loop the two daemons would otherwise form.
#
# systemd targeting: programs.mango (MangoWC) has NO systemd integration at the
# NixOS level — that lives in a Home Manager module itera does not use — so
# `graphical-session.target` is never activated and services bound to it never
# start. Every daemon here is wanted by `default.target` instead and waits for its
# required display sockets (Wayland compositor + XWayland) to appear before doing
# any work. This is the same constraint eiros hit on the same compositor.
#
# Optimization over the original eiros bridge: both watched directions are
# EVENT-DRIVEN (`wl-paste --watch` / `clipnotify`) rather than the original's 100 ms
# busy-poll, which spawned a `wl-paste` process ~10×/second forever just to detect
# changes. They use the exact same `wlr-data-control` / XFixes machinery a one-shot
# read already relied on, so they need nothing extra from mango. The text-only MIME
# filtering and the echo guard are preserved. As a bonus, --watch reports
# CLIPBOARD_STATE, so the bridge refuses to copy password-manager (sensitive)
# content into the persistent X11 clipboard — a leak the blind poll could not have
# avoided. (eiros also had no X11→Wayland daemon at all — copy-out relied on native
# XWayland sync that MangoWC does not provide.)
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

  # Shared shell preludes: block until the required display socket appears, then
  # export the matching env var. mango has no graphical-session.target to order
  # against (see the header), so every daemon self-waits like this.
  awaitWaylandSocket = ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    until find "$runtime_dir" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | grep -q .; do
      sleep 1
    done
    wl_sock=$(find "$runtime_dir" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | sort | head -1)
    export WAYLAND_DISPLAY="''${wl_sock##*/}"
  '';
  awaitX11Socket = ''
    until find /tmp/.X11-unix -maxdepth 1 -name 'X*' 2>/dev/null | grep -q .; do
      sleep 1
    done
    x11_sock=$(find /tmp/.X11-unix -maxdepth 1 -name 'X*' 2>/dev/null | sort | head -1)
    export DISPLAY=":''${x11_sock##*/X}"
  '';

  # Wraps autocutsel to wait for an XWayland socket before starting. `selection`
  # is "CLIPBOARD" or "PRIMARY" (uppercase, passed straight to autocutsel's
  # -selection flag).
  autocutsel-wait =
    selection:
    pkgs.writeShellApplication {
      name = "itera-autocutsel-${lib.toLower selection}";
      runtimeInputs = with pkgs; [
        autocutsel
        findutils
        coreutils
        gnugrep
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

      offered_types=$(wl-paste --list-types 2>/dev/null) || exit 0

      # Only proceed if a text MIME type is on offer.
      printf '%s\n' "$offered_types" \
        | grep -iqE '^text/plain(;charset=.+)?$|^(UTF8_STRING|STRING|TEXT)$' || exit 0

      # Request the matched text type explicitly so wl-paste cannot fall back to
      # image/png when a source offers both. grep -im1 preserves the source's casing.
      req_type=$(printf '%s\n' "$offered_types" | grep -im1 '^text/plain') \
        || req_type=$(printf '%s\n' "$offered_types" | grep -Em1 '^(UTF8_STRING|STRING|TEXT)$') \
        || req_type=""

      current=$(wl-paste -n ''${req_type:+-t "$req_type"} 2>/dev/null) || exit 0
      [ -n "$current" ] || exit 0

      # Break the echo loop: if the X11 CLIPBOARD already holds this (our own prior
      # write, or content the X11→Wayland bridge just mirrored in), skip it.
      x11_current=$(xclip -selection clipboard -o 2>/dev/null) || true
      if [ "$current" = "$x11_current" ]; then
        exit 0
      fi

      printf '%s' "$current" | xclip -selection clipboard
    '';
  };

  # Waits for the Wayland compositor and XWayland sockets, then watches the Wayland
  # clipboard and mirrors text changes into X11 CLIPBOARD via the helper above.
  wayland-to-x11-clipboard = pkgs.writeShellApplication {
    name = "itera-clipboard-wayland-to-x11";
    runtimeInputs = with pkgs; [
      wl-clipboard
      findutils
      coreutils
      gnugrep
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
      findutils
      coreutils
      gnugrep
    ];
    text = ''
      ${awaitWaylandSocket}
      ${awaitX11Socket}

      while true; do
        # Block until the X11 CLIPBOARD/PRIMARY changes. On a transient X error,
        # back off rather than exiting the whole service.
        clipnotify || {
          sleep 1
          continue
        }

        # Only mirror text: check the X11 target list before reading the content.
        targets=$(xclip -selection clipboard -o -t TARGETS 2>/dev/null) || continue
        printf '%s\n' "$targets" \
          | grep -iqE '^(UTF8_STRING|STRING|TEXT)$|^text/plain' || continue

        current=$(xclip -selection clipboard -o 2>/dev/null) || continue
        [ -n "$current" ] || continue

        # Break the echo loop: skip if the Wayland clipboard already holds this
        # (our own prior push, or content the Wayland→X11 bridge just mirrored out).
        wl_current=$(wl-paste -n 2>/dev/null) || true
        if [ "$current" = "$wl_current" ]; then
          continue
        fi

        printf '%s' "$current" | wl-copy
      done
    '';
  };

  # Shared unit shape for the user services.
  bridgeService = description: exec: {
    inherit description;
    wantedBy = [ "default.target" ];
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
      '';
    };

    selectToCopy = mkOption {
      type = bool;
      default = false;
      description = ''
        Also mirror the X11 PRIMARY selection (highlighted text) into CLIPBOARD, so
        selecting text copies it. Off by default; the other bridge services run
        regardless of this toggle.
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

        itera-clipboard-autocutsel-primary = bridgeService "Mirror the X11 CLIPBOARD selection into PRIMARY for XWayland apps" "${autocutsel-wait "PRIMARY"}/bin/itera-autocutsel-primary";
      };
    }

    (mkIf cfg.selectToCopy {
      systemd.user.services.itera-clipboard-autocutsel-clipboard = bridgeService "Mirror the X11 PRIMARY selection into CLIPBOARD (select-to-copy)" "${autocutsel-wait "CLIPBOARD"}/bin/itera-autocutsel-clipboard";
    })

    (mkIf (cfg.steamIntegration && config.programs.steam.enable) {
      programs.steam.extraPackages = with pkgs; [
        wl-clipboard-x11
        xdotool
      ];
    })
  ]);
}
