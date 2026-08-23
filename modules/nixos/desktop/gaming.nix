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
    # The hardening battery leaves nix-mineral's `settings.system.yama` at its
    # "restricted" default (kernel.yama.ptrace_scope = 3), which forbids ptrace
    # outright. Wine/Proton's `wineserver` ptraces its own children, so Proton
    # titles spam `kernel: ptrace attach of "…" was attempted by "…/wineserver"`
    # and kernel-adjacent anti-cheats can refuse to run. Upstream nix-mineral
    # calls this out and its `compatibility` preset sets `yama = "relaxed"`
    # (scope 1: a parent may trace its own children — exactly Wine's pattern)
    # for this reason. Warn rather than relax it here: weakening hardening is
    # the host's call, not something a gaming battery should do silently.
    warnings =
      lib.optional
        (config.itera.hardening.enable && config.nix-mineral.settings.system.yama == "restricted")
        ''
          itera.gaming is enabled but nix-mineral.settings.system.yama = "restricted"
          (kernel.yama.ptrace_scope = 3), which blocks all ptrace. Wine/Proton needs
          it for its own child processes: expect ptrace denials in the journal and
          anti-cheats that refuse to start. Set
          nix-mineral.settings.system.yama = "relaxed" (or add "compatibility" to
          itera.hardening.preset) if you hit that.
        '';

    # nix-mineral disables the whole `joystick-drivers` combo (secureblue's list),
    # which sweeps up `joydev` — the driver behind the legacy `/dev/input/js*`
    # joystick API. udev tries to autoload it for any input device whose modalias
    # matches, so on a host with ordinary HID peripherals it also emits a handful
    # of `udev-worker: Error running install command '…/nm-disabled-module-alert'
    # for module joydev: retcode 1` errors every boot.
    #
    # Modern controllers reach games over evdev (SDL2, Steam Input) and are NOT
    # affected — `xpad` and every `hid-*` gamepad driver (hid-nintendo,
    # hid-playstation, hid-sony, hid-steam) are absent from that combo, so they
    # keep loading. What breaks is anything still reading `js*`: SDL1-era titles
    # and older native Linux ports simply see no controller at all.
    #
    # Re-enable just `joydev` rather than the whole combo: the rest of it is
    # gameport/parallel-port/serial adapters (db9, gamecon, turbografx, sidewinder,
    # …) that a modern gaming host has no use for, and leaving them disabled keeps
    # the attack surface tight. `disable.<module>` is a freeform per-module knob
    # that takes priority over the combo, so this is a targeted carve-out and not
    # a blanket relaxation of the hardening layer. Unlike the yama case above this
    # IS flipped for you: it is narrow, and a gaming battery that silently drops
    # legacy joystick support isn't delivering what it advertises. mkDefault so a
    # host that would rather keep `joydev` off can force it back. Not gated on
    # `itera.hardening.enable`: nix-mineral's own module already no-ops the whole
    # disable list when it is off, and gating here would miss a host that turns
    # nix-mineral on directly.
    nix-mineral.kernel-modules.disable.joydev = mkDefault false;

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
