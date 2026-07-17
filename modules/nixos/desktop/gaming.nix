# itera's gaming battery.
#
# Steam (with Proton-GE), gamemode, and gamescope. Opt-IN (off by default): a
# desktop-adjacent battery like the other `itera.desktop.*` ones, but not wanted
# on every machine.
#
# The 32-bit graphics libraries Steam/Wine need are provided by the graphics/
# nvidia batteries (see modules/nixos/core/nvidia.nix, which enables 32-bit GL for
# Steam) — this module deliberately does NOT set `hardware.graphics.enable32Bit`
# so there is a single owner of the graphics stack.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool listOf package;

  cfg = config.itera.gaming;
in
{
  options.itera.gaming = {
    enable = mkEnableOption "Steam, gamemode, and gamescope";

    protonPackages = mkOption {
      type = listOf package;
      default = [ pkgs.proton-ge-bin ];
      defaultText = lib.literalExpression "[ pkgs.proton-ge-bin ]";
      description = "Extra Steam compatibility tools (Proton builds) made available in Steam.";
    };

    gamescope.enable = mkOption {
      type = bool;
      default = true;
      description = "Install the gamescope micro-compositor (for per-game upscaling/frame limiting).";
    };

    gamemode.enable = mkOption {
      type = bool;
      default = true;
      description = "Enable Feral GameMode (on-demand performance governor for games).";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    programs = {
      steam = {
        enable = mkDefault true;
        extraCompatPackages = cfg.protonPackages;
      };

      # The steam module ships its own `mkDefault` for gamescope; assign at normal
      # priority so the `itera.gaming.gamescope.enable` knob is the single source
      # of truth (a consumer can still force it with `lib.mkForce`).
      gamescope.enable = cfg.gamescope.enable;
      gamemode.enable = mkDefault cfg.gamemode.enable;
    };
  };
}
