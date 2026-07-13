# itera's GUI text-editor battery (Zed).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and, until now,
# shipped no editor — nothing claimed the `text/plain` handler, so double-clicking a
# text file in Nemo (or `xdg-open`-ing one) had no default, and the desktop had no
# editor spawn bind. This battery ships Zed: a fast, Wayland-native, GPU-accelerated
# editor, and makes it the session's default handler for text/source files.
#
# This is a GUI-default editor only: it does NOT set `EDITOR`/`VISUAL`, so terminal
# tooling and `git commit` keep the system default (nano). It installs the package,
# claims the text MIME handlers, and wires the mango `SUPER+e` bind (mirroring how
# the terminal/browser batteries wire `SUPER+t`/`SUPER+b`). nixpkgs renames Zed's
# CLI to `zeditor` (the `.desktop` id is `dev.zed.Zed.desktop`).
#
# This module is the SYSTEM half: it installs the package and wires the handler +
# compositor bind. The per-user config (`~/.config/zed/settings.json`, with
# telemetry disabled) is written by the matching home battery `itera.programs.zed`
# (`modules/hjem/programs/zed.nix`), whose `enable` follows this system toggle by
# default.
#
# There is no system state to persist under impermanence — per-user Zed settings
# live in $HOME (covered by the hjem / `itera.impermanence.users` home-persistence
# path), same as the terminal, browser, and file-manager batteries.
#
# Opt-OUT (default ON): set `itera.desktop.editor.enable = false` to drop it (or to
# ship your own editor).
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

  cfg = config.itera.desktop.editor;
in
{
  options.itera.desktop.editor = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install the Zed editor, make it the default handler for text/source files,
        and wire the mango `SUPER+e` keybind to it. On by default whenever
        {option}`itera.enable` is set; set to `false` to opt out (or to ship your
        own editor). This does not set `EDITOR`/`VISUAL` — terminal and `git`
        keep the system default.
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # Zed build) while keeping the handler + compositor wiring below.
    package = mkPackageOption pkgs "zed-editor" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ cfg.package ];

    # Make Zed the session's default handler for text + common source files. A
    # focused set (like the browser battery) rather than an exhaustive list;
    # anything else keeps whatever handler its own battery claims. The `.desktop`
    # id `dev.zed.Zed.desktop` is installed by the nixpkgs package.
    xdg.mime.defaultApplications = {
      "text/plain" = mkDefault "dev.zed.Zed.desktop";
      "text/markdown" = mkDefault "dev.zed.Zed.desktop";
      "application/json" = mkDefault "dev.zed.Zed.desktop";
      "application/x-shellscript" = mkDefault "dev.zed.Zed.desktop";
      "text/x-python" = mkDefault "dev.zed.Zed.desktop";
      "text/x-csrc" = mkDefault "dev.zed.Zed.desktop";
      "text/x-nix" = mkDefault "dev.zed.Zed.desktop";
    };

    # Light up the mango SUPER+e spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`. nixpkgs renames the CLI to
    # `zeditor` (not `zed`), which opens the GUI directly.
    itera.desktop.mango.commands.editor = mkDefault "zeditor";
  };
}
