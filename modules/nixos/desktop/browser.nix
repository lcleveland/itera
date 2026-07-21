# itera's web-browser battery (Vivaldi).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and needs a
# browser to claim the `x-scheme-handler/https` handler and the desktop's browser
# spawn bind. This battery ships Vivaldi: a feature-rich Chromium-based browser
# with built-in tab management, mail/calendar, and its own account sync. It is
# the desktop's daily-driver browser default.
#
# This module installs the package, makes it the session's default handler for web
# schemes + HTML, forces native Wayland rendering (Ozone), and wires the mango
# `SUPER+b` bind (mirroring how the terminal battery wires `SUPER+t`). nixpkgs'
# `vivaldi` package provides the `vivaldi` binary and the `vivaldi-stable.desktop`
# app id. It is built with proprietary media codecs (H.264/AAC) and Widevine so
# common web video and DRM streaming work out of the box.
#
# Vivaldi is unfree; itera allows unfree packages by default via
# `itera.nix.allowUnfree`, so nothing extra is needed on the default path.
#
# There is no system state to persist under impermanence, and the per-user
# profile lives at `~/.config/vivaldi` — already inside the curated `.config`
# home dir the impermanence battery persists, so bookmarks/logins/history survive
# the wiped root with no browser-specific wiring.
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

  # Build Vivaldi with proprietary media codecs (H.264/AAC — most web video) and
  # Widevine (DRM streaming like Netflix/Spotify), both off in the nixpkgs
  # default. This is the desktop's daily-driver browser, so it needs them to be
  # usable. Skipped when the consumer drops the package (`package = null`).
  browserPackage =
    if cfg.package != null then
      cfg.package.override {
        proprietaryCodecs = true;
        enableWidevine = true;
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
        Install Vivaldi, make it the default web handler, and wire the mango
        `SUPER+b` keybind to it. On by default whenever {option}`itera.enable`
        is set; set to `false` to opt out (or to ship your own browser).
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # Vivaldi build) while keeping the handler + compositor wiring below.
    package = mkPackageOption pkgs "vivaldi" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ browserPackage ];

    # Force native Wayland rendering via Ozone. Chromium-family browsers default
    # to XWayland otherwise, and the stack is Wayland-only (mango). nixpkgs'
    # Chromium/Electron wrappers read `NIXOS_OZONE_WL` and pass the Ozone Wayland
    # hint through.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # Make Vivaldi the session's default handler for web schemes + HTML.
    xdg.mime.defaultApplications = {
      "x-scheme-handler/http" = mkDefault "vivaldi-stable.desktop";
      "x-scheme-handler/https" = mkDefault "vivaldi-stable.desktop";
      "text/html" = mkDefault "vivaldi-stable.desktop";
      "x-scheme-handler/about" = mkDefault "vivaldi-stable.desktop";
      "x-scheme-handler/unknown" = mkDefault "vivaldi-stable.desktop";
    };

    # Light up the mango SUPER+b spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`. mango's `spawn` execs the
    # command directly with no shell, and `vivaldi` is a directly-executable
    # binary, so the bare command works.
    itera.desktop.mango.commands.browser = mkDefault "vivaldi";
  };
}
