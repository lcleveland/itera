# itera's gaming battery.
#
# Steam (with Proton-GE), gamemode, and gamescope. Opt-IN (off by default): a
# desktop-adjacent battery like the other `itera.desktop.*` ones, but not wanted
# on every machine.
#
# 32-bit support comes from two places, neither of which this module has to own
# the graphics stack for:
#   • 32-bit GL *libraries*: the upstream `programs.steam` module already turns on
#     `hardware.graphics.enable` + `enable32Bit`, so we don't set them here (the
#     nvidia battery also sets `enable32Bit`, redundantly).
#   • 32-bit *execution*: itera's hardening battery sets `ia32_emulation=0`, which
#     breaks every i686 binary Steam/Proton ship — so we re-enable multilib below.
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

    # Steam and Proton ship 32-bit (i686) executables, so the host kernel must be
    # able to run them. itera's hardening battery (nix-mineral) sets
    # `ia32_emulation=0` by default (its `system.multilib = false`), which disables
    # the 32-bit syscall path and makes every i686 binary — including Nix's own
    # i686 builders — fail with "Exec format error". Re-enable multilib whenever
    # gaming is on: scoped to hosts that opt into Steam, so non-gaming hosts keep
    # the tighter default. mkDefault so a consumer can still force it back off, and
    # it wins over the aggressive hardening presets (verified against `maximum`).
    nix-mineral.settings.system.multilib = mkDefault true;
  };
}
