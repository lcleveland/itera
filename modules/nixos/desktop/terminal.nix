# itera's terminal-emulator battery (Ghostty).
#
# itera targets a Wayland-only desktop (mango + DankMaterialShell) and, until now,
# shipped no terminal — the mango `SUPER+t` bind stayed dead unless the consumer
# named one (see `itera.desktop.mango.commands.terminal`). This battery ships
# Ghostty: a fast, Wayland-native, GPU-accelerated terminal. DankMaterialShell
# already integrates with it (matugen theming template + plugins that expect
# `ghostty`), so it slots cleanly into the stack.
#
# This module is the SYSTEM half: it installs the package and wires the compositor
# bind. The per-user config (font size, padding, …) is written by the matching
# home battery `itera.programs.ghostty` (`modules/hjem/programs/ghostty.nix`),
# whose `enable` follows this system toggle by default.
#
# There is no system state to persist under impermanence — per-user Ghostty
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
        Install the Ghostty terminal emulator and wire the mango `SUPER+t`
        keybind to it. On by default whenever {option}`itera.enable` is set; set
        to `false` to opt out (or to ship your own terminal).
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # Ghostty build) while keeping the compositor wiring below.
    package = mkPackageOption pkgs "ghostty" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ cfg.package ];

    # Light up the mango SUPER+t spawn bind. The option is always declared by the
    # mango module (even when mango is disabled), and `mkDefault` lets a consumer
    # override the command or clear it back to `null`.
    itera.desktop.mango.commands.terminal = mkDefault "ghostty";
  };
}
