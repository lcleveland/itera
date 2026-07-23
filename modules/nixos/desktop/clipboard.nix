# itera's Wayland↔X11 clipboard bridge battery.
#
# XWayland apps (Proton games, legacy X11 tools) live in their own X11 clipboard
# world: text copied in a Wayland app is not visible to them, and vice versa.
# This battery bridges the two so copy/paste works across the boundary, and — as a
# side effect — stops binary image data (screenshots) from being mangled into a
# garbled "Long Text" entry in the DankMaterialShell clipboard history.
#
# It ships three things:
#   • wl-clipboard on PATH (wl-copy/wl-paste) for terminal clipboard access.
#   • The bridge daemons (below), as systemd *user* services.
#   • When Steam is on (itera.gaming), wl-clipboard-x11 + xdotool injected into
#     Steam's FHS container so Proton games can reach the clipboard atoms.
#
# systemd targeting: programs.mango (MangoWC) has NO systemd integration at the
# NixOS level — that lives in a Home Manager module itera does not use — so
# `graphical-session.target` is never activated and services bound to it never
# start. Every daemon here is wanted by `default.target` instead and waits for its
# required display sockets (Wayland compositor + XWayland) to appear before doing
# any work. This is the same constraint eiros hit on the same compositor.
#
# Optimization over the original eiros bridge: the Wayland→X11 direction is
# EVENT-DRIVEN via `wl-paste --watch` rather than a 100 ms busy-poll. The poll
# spawned a `wl-paste` process ~10×/second forever just to detect changes; `--watch`
# blocks and fires only when the clipboard actually changes, using the exact same
# `wlr-data-control` protocol the one-shot reads already rely on (so it needs
# nothing extra from mango). The careful text-only MIME filtering and the X11 echo
# guard are preserved. As a bonus, --watch reports CLIPBOARD_STATE, so the bridge
# now refuses to copy password-manager (sensitive) content into the persistent X11
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
        # Wait for any XWayland socket to appear.
        until find /tmp/.X11-unix -maxdepth 1 -name 'X*' 2>/dev/null | grep -q .; do
          sleep 1
        done
        # Use the first available X11 display.
        sock=$(find /tmp/.X11-unix -maxdepth 1 -name 'X*' 2>/dev/null | sort | head -1)
        export DISPLAY=":''${sock##*/X}"
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

      # Break the XWayland echo loop: if the compositor mirrors our own X11 write
      # back to Wayland, --watch fires again with identical content — skip it.
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
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      # Wait for the Wayland compositor socket.
      until find "$runtime_dir" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | grep -q .; do
        sleep 1
      done
      sock=$(find "$runtime_dir" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | sort | head -1)
      export WAYLAND_DISPLAY="''${sock##*/}"

      # Wait for an XWayland socket.
      until find /tmp/.X11-unix -maxdepth 1 -name 'X*' 2>/dev/null | grep -q .; do
        sleep 1
      done
      x11_sock=$(find /tmp/.X11-unix -maxdepth 1 -name 'X*' 2>/dev/null | sort | head -1)
      export DISPLAY=":''${x11_sock##*/X}"

      # Event-driven: fires only when the Wayland clipboard changes.
      exec wl-paste --watch itera-clipboard-sync-once
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
        Run the Wayland↔X11 clipboard bridge so copy/paste works between Wayland
        apps and XWayland apps (Proton games, legacy X11 tools), install
        {command}`wl-clipboard`, and — when {option}`itera.gaming` is on — inject the
        clipboard tools into Steam's container. Also stops binary image data from
        showing up as garbled "Long Text" in the DankMaterialShell clipboard
        history. On by default whenever the mango desktop is enabled; set to `false`
        to opt out. Inert on a headless host (no compositor).
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
