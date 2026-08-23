# itera's calculator battery (GNOME Calculator).
#
# Native NixOS/nixpkgs feature (no flake input): installs GNOME Calculator and
# wires the desktop's calculator spawn bind to it. The desktop shipped no
# calculator at all, so the `XF86Calculator` key most keyboards carry was a dead
# key and there was nothing behind the app launcher's most mundane request.
#
# GNOME Calculator is GTK4/libadwaita and Wayland-native, so it fits the
# mango/DankMaterialShell session without dragging in a session-manager stack the
# way a full GNOME or KDE calculator would. Beyond basic arithmetic it covers the
# modes a daily driver actually reaches for — scientific, programming (bases,
# bitwise), unit and currency conversion — and its `gcalccmd` binary gives the
# same evaluator on the command line.
#
# It keeps history and preferences (angle units, word size, precision) in
# GSettings, so this battery enables dconf the way the file-manager battery does.
# There is no system state to persist under impermanence — that dconf database
# lives at `~/.config/dconf`, already inside the curated `.config` home dir the
# impermanence battery persists, so history and preferences survive the wiped
# root with no calculator-specific wiring.
#
# No mime handler: a calculator claims no content type. The only session wiring
# is the compositor bind (SUPER+c and the `XF86Calculator` key), set here and
# rendered by the curated mango keybind set.
#
# Opt-OUT (default ON): set `itera.desktop.calculator.enable = false` to drop it.
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

  cfg = config.itera.desktop.calculator;
in
{
  options.itera.desktop.calculator = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install GNOME Calculator and wire the mango `SUPER+c` keybind (and the
        `XF86Calculator` key) to it. On by default whenever {option}`itera.enable`
        is set; set to `false` to opt out (or to ship your own calculator).
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # calculator) while keeping the compositor wiring below.
    package = mkPackageOption pkgs "gnome-calculator" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ cfg.package ];

    # Where GNOME Calculator stores history and preferences (angle unit, word
    # size, precision). Without dconf the app still runs, but every setting —
    # and the history stack — resets on each launch.
    programs.dconf.enable = mkDefault true;

    # Light up the mango calculator spawn binds. The option is always declared by
    # the mango module (even when mango is disabled), and `mkDefault` lets a
    # consumer override the command or clear it back to `null`. mango's `spawn`
    # execs the command directly with no shell, and `gnome-calculator` is a
    # directly-executable binary, so the bare command works (unlike `wezterm`,
    # which needs its `start` subcommand).
    itera.desktop.mango.commands.calculator = mkDefault "gnome-calculator";
  };
}
