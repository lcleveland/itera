# itera's power battery.
#
# Adds UPower, the daemon that reports battery and power-device state over
# D-Bus. The DankMaterialShell battery indicator and its lock-before-suspend
# logic read from it. `power-profiles-daemon` is already enabled by the DMS
# module, but that only switches performance profiles — it is not the battery
# reporter, so UPower is still needed. TLP is deliberately NOT added: it is
# mutually exclusive with power-profiles-daemon.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# with `mkDefault`, so it is on by default yet overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.power;
in
{
  options.itera.power = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Enable UPower battery / power-device reporting.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.upower.enable = mkDefault true;
  };
}
