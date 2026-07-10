# itera's web-browser battery (ungoogled-chromium).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and, until now,
# shipped no browser — nothing claimed the `x-scheme-handler/https` handler and
# the desktop had no browser spawn bind. This battery ships ungoogled-chromium:
# upstream Chromium with Google's integration/telemetry and background phone-homes
# stripped out and privacy patches applied, while keeping Chromium's sandbox. It
# is the security/privacy-focused Chromium default for the stack.
#
# This module installs the package, makes it the session's default handler for web
# schemes + HTML, and wires the mango `SUPER+b` bind (mirroring how the terminal
# battery wires `SUPER+t`). ungoogled-chromium and nixpkgs' chromium share the
# `chromium` binary and the `chromium-browser.desktop` app id.
#
# There is no system state to persist under impermanence — per-user browser
# profiles live in $HOME (covered by the hjem / `itera.impermanence.users`
# home-persistence path), same as the terminal and file-manager batteries.
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
in
{
  options.itera.desktop.browser = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install ungoogled-chromium, make it the default web handler, and wire the
        mango `SUPER+b` keybind to it. On by default whenever {option}`itera.enable`
        is set; set to `false` to opt out (or to ship your own browser).
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # Chromium build) while keeping the handler + compositor wiring below.
    package = mkPackageOption pkgs "ungoogled-chromium" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ cfg.package ];

    # Make Chromium the session's default handler for web schemes + HTML.
    xdg.mime.defaultApplications = {
      "x-scheme-handler/http" = mkDefault "chromium-browser.desktop";
      "x-scheme-handler/https" = mkDefault "chromium-browser.desktop";
      "text/html" = mkDefault "chromium-browser.desktop";
      "x-scheme-handler/about" = mkDefault "chromium-browser.desktop";
      "x-scheme-handler/unknown" = mkDefault "chromium-browser.desktop";
    };

    # Light up the mango SUPER+b spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`. The binary is `chromium`
    # for both chromium and ungoogled-chromium.
    itera.desktop.mango.commands.browser = mkDefault "chromium";
  };
}
