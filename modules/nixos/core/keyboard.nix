# itera's keyboard-layout battery.
#
# One place to set the XKB layout/variant/options, applied consistently across
# every input surface: the X/Wayland server, the virtual console (via
# `console.useXkbConfig`), and — through the mango renderer and DMS greeter — the
# mango session and login screen. Without this the console would keep the default
# `us` while a Wayland session used something else.
#
# Opt-out like the other core batteries (gated on `itera.enable`, mkDefault
# values); the defaults are a plain `us` layout, so leaving it untouched changes
# nothing. Set e.g. `itera.keyboard.variant = "colemak_dh"` for an alternative.
#
# The mango wiring lives in the renderer (modules/hjem/programs/mango.nix) and the
# greeter battery (modules/nixos/desktop/dankmaterialshell.nix), which read the
# resulting `services.xserver.xkb.*` values — so there is no per-user duplication.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) str;

  cfg = config.itera.keyboard;
in
{
  options.itera.keyboard = {
    layout = mkOption {
      type = str;
      default = "us";
      example = "us,de";
      description = "XKB keyboard layout (`services.xserver.xkb.layout`).";
    };

    variant = mkOption {
      type = str;
      default = "";
      example = "colemak_dh";
      description = "XKB layout variant (`services.xserver.xkb.variant`). Empty for the base layout.";
    };

    options = mkOption {
      type = str;
      default = "";
      example = "ctrl:nocaps";
      description = "XKB options (`services.xserver.xkb.options`), comma-separated.";
    };
  };

  config = mkIf config.itera.enable {
    services.xserver.xkb = {
      layout = mkDefault cfg.layout;
      variant = mkDefault cfg.variant;
      options = mkDefault cfg.options;
    };

    # Make the virtual console follow the XKB config above instead of its own
    # separate keymap, so the layout is identical from the TTY to the desktop.
    console.useXkbConfig = mkDefault true;
  };
}
