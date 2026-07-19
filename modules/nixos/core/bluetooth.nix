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

      # nix-mineral's `kicksecure-bluetooth` (on via the hardening battery) mkForces
      # a whole `/etc/bluetooth/main.conf` borrowed from Kicksecure. That file puts
      # the LE-privacy key under `[Policy]` (`Privacy=network/on`), but BlueZ only
      # accepts `Privacy` under `[General]` — so bluetoothd logs
      # `Unknown key Privacy for group Policy` and the privacy hardening is silently
      # a no-op. We drop that file (below) and re-declare the same Kicksecure keys
      # here with `Privacy` in its correct group, so the hardening actually applies
      # and the warning goes away.
      settings = {
        General = {
          PairableTimeout = mkDefault 30;
          DiscoverableTimeout = mkDefault 30;
          MaxControllers = mkDefault 1;
          TemporaryTimeout = mkDefault 0;
          Privacy = mkDefault "network/on"; # moved here from Kicksecure's [Policy]
        };
        # Power the adapter on automatically (and reconnect known devices) at
        # boot, matching `powerOnBoot` above and itera's opt-out intent — the
        # battery enables BlueZ and DankMaterialShell ships a Bluetooth widget, so
        # a controller that stays dark by default is a bug, not hardening. This is
        # a deliberate divergence from Kicksecure's radio-off-by-default posture
        # (which mkForced this to `false`); `mkDefault` leaves it overridable for a
        # locked-down host that wants the adapter off until asked.
        Policy.AutoEnable = mkDefault true;
      };
    };

    # Drop nix-mineral's mkForced main.conf so the corrected `settings` above win.
    # Gated on the hardening layer being present, so this stays a no-op (no phantom
    # option touched) on a host that has turned nix-mineral off.
    nix-mineral = mkIf config.nix-mineral.enable {
      settings.etc.kicksecure-bluetooth = mkDefault false;
    };
  };
}
