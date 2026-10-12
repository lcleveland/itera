# itera's terminal-emulator battery (WezTerm).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and, until now,
# shipped no terminal — the mango `SUPER+t` bind stayed dead unless the consumer
# named one (see `itera.desktop.mango.commands.terminal`). This battery ships
# WezTerm: a fast, Wayland-native, GPU-accelerated terminal with a Lua config.
#
# WezTerm embeds no font. Its font is the look's mono font (itera Mono, with the
# Nerd glyphs CLI tooling needs), which the fonts battery installs.
#
# This module is the SYSTEM half: it installs the package and wires the
# compositor bind. The curated config options (font size, padding, …) are declared
# by `modules/programs/wezterm.nix` — settable system-wide at
# `itera.programs.wezterm.*` and per-user at `itera.users.<name>.programs.wezterm.*`
# — and rendered by `modules/hjem/programs/wezterm.nix`, gated on this system toggle.
#
# There is no system state to persist under impermanence — per-user WezTerm
# settings live in $HOME (covered by the hjem / `itera.impermanence.users`
# home-persistence path), same as the file-manager battery.
#
# Opt-OUT (default ON): set `itera.desktop.terminal.enable = false` to drop it.
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

  cfg = config.itera.desktop.terminal;
in
{
  options.itera.desktop.terminal = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install the WezTerm terminal emulator and wire the mango `SUPER+t`
        keybind to it. On by default whenever {option}`itera.enable` is set; set
        to `false` to opt out (or to ship your own terminal).
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # WezTerm build) while keeping the compositor wiring below.
    package = mkPackageOption pkgs "wezterm" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ cfg.package ];

    # Light up the mango SUPER+t spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`.
    #
    # Must be `wezterm start`, not bare `wezterm`: mango `spawn` execs the command
    # directly (no shell), and `wezterm` with no subcommand is a usage error that
    # exits immediately — so SUPER+t would flash nothing. `start` is the GUI
    # subcommand (same as WezTerm's own `.desktop` `Exec=wezterm start`, which the
    # app launcher uses successfully).
    itera.desktop.mango.commands.terminal = mkDefault "wezterm start";
  };
}
