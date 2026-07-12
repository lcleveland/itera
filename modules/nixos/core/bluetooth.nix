# itera's Bluetooth battery.
#
# Brings up the BlueZ stack so adapters actually work — the DankMaterialShell
# bar ships a Bluetooth widget, but nothing sits behind it until this turns on
# `hardware.bluetooth`. No blueman: DMS provides the pairing UI.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# with `mkDefault` values, so it is on by default yet fully overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.bluetooth;
in
{
  options.itera.bluetooth = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Enable Bluetooth hardware support (BlueZ).";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    hardware.bluetooth = {
      enable = mkDefault true;
      powerOnBoot = mkDefault true;
    };
  };
}
