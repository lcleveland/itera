# itera's web-browser battery (LibreWolf).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and needs a
# browser to claim the `x-scheme-handler/https` handler and the desktop's browser
# spawn bind. This battery ships LibreWolf: a privacy-hardened fork of Firefox
# with telemetry removed and privacy/security defaults turned up out of the box.
# It is the security/privacy-focused browser default for the stack.
#
# This module installs the package, makes it the session's default handler for web
# schemes + HTML, forces native Wayland rendering, and wires the mango `SUPER+b`
# bind (mirroring how the terminal battery wires `SUPER+t`). nixpkgs' `librewolf`
# package provides the `librewolf` binary and the `librewolf.desktop` app id.
#
# There is no system state to persist under impermanence, but the per-user
# profile lives at `~/.librewolf` — none of the curated home dirs
# (`.config`/`.local/share`/`.cache`/`Documents`). The impermanence battery
# persists it via a browser-gated home entry (`.librewolf` is added to each
# user's persisted dirs whenever this battery is on), so bookmarks/logins/history
# survive the wiped root.
#
# Opt-OUT (default ON): set `itera.desktop.browser.enable = false` to drop it (or
# to ship your own browser).
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

  cfg = config.itera.desktop.browser;

  # LibreWolf ships with Firefox Sync (Mozilla accounts) disabled by default —
  # its bundled `librewolf.cfg` sets `defaultPref("identity.fxaccounts.enabled",
  # false)`. When `enableSync` is on we append an `extraPrefs` line that flips
  # that default back to `true`. nixpkgs concatenates `extraPrefs` *after*
  # `librewolf.cfg` in the generated `mozilla.cfg`, and the later `defaultPref`
  # wins, so Sync becomes available in the UI without locking the pref (users can
  # still turn it off per-profile).
  browserPackage =
    if cfg.package != null && cfg.enableSync then
      cfg.package.override {
        extraPrefs = ''
          defaultPref("identity.fxaccounts.enabled", true);
        '';
      }
    else
      cfg.package;
in
{
  options.itera.desktop.browser = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install LibreWolf, make it the default web handler, and wire the mango
        `SUPER+b` keybind to it. On by default whenever {option}`itera.enable`
        is set; set to `false` to opt out (or to ship your own browser).
      '';
    };

    enableSync = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable Firefox Sync (Mozilla accounts) in LibreWolf, which the upstream
        build disables by default. On by default; set to `false` to keep Sync
        turned off. Only takes effect when {option}`package` is non-null.
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # LibreWolf build) while keeping the handler + compositor wiring below.
    package = mkPackageOption pkgs "librewolf" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ browserPackage ];

    # Force native Wayland rendering. Firefox-family browsers don't reliably
    # auto-detect Wayland, and the stack is Wayland-only (mango); without this
    # LibreWolf falls back to XWayland.
    environment.sessionVariables.MOZ_ENABLE_WAYLAND = "1";

    # Make LibreWolf the session's default handler for web schemes + HTML.
    xdg.mime.defaultApplications = {
      "x-scheme-handler/http" = mkDefault "librewolf.desktop";
      "x-scheme-handler/https" = mkDefault "librewolf.desktop";
      "text/html" = mkDefault "librewolf.desktop";
      "x-scheme-handler/about" = mkDefault "librewolf.desktop";
      "x-scheme-handler/unknown" = mkDefault "librewolf.desktop";
    };

    # Light up the mango SUPER+b spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`. mango's `spawn` execs the
    # command directly with no shell, and `librewolf` is a directly-executable
    # binary, so the bare command works.
    itera.desktop.mango.commands.browser = mkDefault "librewolf";
  };
}
