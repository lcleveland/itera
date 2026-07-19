# itera's gaming battery.
#
# Steam (with Proton-GE), gamemode, and gamescope. Opt-IN (off by default): a
# desktop-adjacent battery like the other `itera.desktop.*` ones, but not wanted
# on every machine.
#
# 32-bit support comes from two places, neither of which this module has to own:
#   • 32-bit GL *libraries*: the upstream `programs.steam` module already turns on
#     `hardware.graphics.enable` + `enable32Bit`, so we don't set them here (the
#     nvidia battery also sets `enable32Bit`, redundantly).
#   • 32-bit *execution*: kept on system-wide by the hardening battery (which owns
#     the `ia32_emulation` kernel param — see modules/nixos/core/hardening.nix).
#     It must stay on even without gaming, otherwise the running system can't build
#     a config that pulls in 32-bit closures (Steam) — a bootstrap deadlock.
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
