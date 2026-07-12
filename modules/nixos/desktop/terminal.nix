# itera's terminal-emulator battery (WezTerm).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and, until now,
# shipped no terminal — the mango `SUPER+t` bind stayed dead unless the consumer
# named one (see `itera.desktop.mango.commands.terminal`). This battery ships
# WezTerm: a fast, Wayland-native, GPU-accelerated terminal with a Lua config.
#
# Unlike some GPU terminals, WezTerm embeds no font, so this battery also installs
# JetBrains Mono Nerd Font system-wide (`fonts.packages`) and the home battery
# points WezTerm at it — otherwise the shell's glyph-heavy tooling (`eza --icons`,
# the spaceship prompt) would render as tofu.
#
# This module is the SYSTEM half: it installs the package + font and wires the
# compositor bind. The per-user config (font size, padding, …) is written by the
# matching home battery `itera.programs.wezterm`
# (`modules/hjem/programs/wezterm.nix`), whose `enable` follows this system toggle
# by default.
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

    # WezTerm embeds no font. Install JetBrains Mono Nerd Font so the home
    # battery's `fontFamily` default resolves and the shell's Nerd-Font glyphs
    # render. Gated on the package being present (dropping the terminal drops its
    # font too).
    fonts.packages = mkIf (cfg.package != null) [ pkgs.nerd-fonts.jetbrains-mono ];

    # Light up the mango SUPER+t spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`.
    itera.desktop.mango.commands.terminal = mkDefault "wezterm";
  };
}
