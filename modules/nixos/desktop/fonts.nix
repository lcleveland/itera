# itera's fonts battery.
#
# Installs the look's fonts system-wide (Roboto Flex, itera Mono and the Noto
# fallbacks) and makes the system look's font tokens fontconfig's sans-serif,
# monospace and emoji defaults, so every app that asks fontconfig gets them.
# Apps with their own font settings (DMS, WezTerm, Zed) take the tokens from
# `iteraLib.look.resolve` in their batteries. See
# docs/look.md#typography-icons-cursor.
#
# Opt-out like the other batteries: gated on the master `itera.enable`, with
# the fontconfig defaults as `mkDefault`s so they stay overridable.
{
  config,
  lib,
  pkgs,
  iteraLib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.fonts;
  inherit ((iteraLib.look.resolve config null)) fonts;
in
{
  options.itera.desktop.fonts.enable = mkOption {
    type = bool;
    default = true;
    description = ''
      Install the look's fonts and make them fontconfig's defaults. Fontconfig is
      system-wide, so per-user font tokens don't reach it. Turned off, DMS, WezTerm
      and Zed still name the look's fonts, so install them (or override the font
      tokens) yourself.
    '';
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    fonts.packages = [
      pkgs.roboto-flex
      (import ../../../pkgs { inherit pkgs; }).itera-mono
      pkgs.noto-fonts
      pkgs.noto-fonts-color-emoji
    ];

    fonts.fontconfig.defaultFonts = {
      sansSerif = mkDefault [ fonts.sans ];
      monospace = mkDefault [ fonts.mono ];
      emoji = mkDefault [ fonts.emoji ];
    };
  };
}
