# itera's networking battery: hostname and NetworkManager.
#
# Names the machine and brings up NetworkManager as the default connection
# manager (works out of the box for both wired and Wi-Fi). Gated on the master
# `itera.enable` with `mkDefault` values, so everything is opt-out and overridable.
#
# Also pins a *stable* (but still non-hardware) MAC address, opting out of the
# per-connection MAC randomization that the hardening layer (nix-mineral) turns
# on by default — that randomization hands the machine a fresh DHCP lease/IP on
# every reboot. See `stableMac.enable` below.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) bool str;

  cfg = config.itera.networking;
in
{
  options.itera.networking = {
    hostName = mkOption {
      type = str;
      default = "itera";
      example = "my-machine";
      description = "System hostname.";
    };

    networkmanager.enable = mkOption {
      type = bool;
      default = true;
      description = "Use NetworkManager to manage network connections.";
    };

    stableMac.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Use a stable (but still non-hardware) MAC address for NetworkManager
        connections instead of the per-connection random MAC that the hardening
        layer (nix-mineral) enables by default. A stable MAC keeps the DHCP
        lease — and therefore the machine's IP — constant across reboots,
        deriving from NetworkManager's persisted secret_key. Set to false to
        restore nix-mineral's per-connection MAC randomization.
      '';
    };
  };

  config = mkIf config.itera.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.hostName != "";
          message = "itera.networking.hostName must not be empty.";
        }
      ];

      networking = {
        hostName = mkDefault cfg.hostName;
        networkmanager.enable = mkDefault cfg.networkmanager.enable;
      };
    }

    (mkIf cfg.stableMac.enable {
      # Stop nix-mineral's per-connection MAC randomization (which hands us a
      # new DHCP lease/IP every reboot) and pin a stable, deterministic-but-
      # private MAC. Disabling the upstream toggle mirrors how hardening.nix
      # opts out of nix-mineral's generic-machine-id. Scan-time randomization
      # is preserved.
      nix-mineral.settings.network.random-mac = mkDefault false;
      networking.networkmanager = {
        ethernet.macAddress = mkDefault "stable";
        wifi = {
          macAddress = mkDefault "stable";
          scanRandMacAddress = mkDefault true;
        };
      };
    })
  ]);
}
