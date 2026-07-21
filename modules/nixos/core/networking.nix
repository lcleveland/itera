# itera's networking battery: hostname, NetworkManager, and a caching resolver.
#
# Names the machine and brings up NetworkManager as the default connection
# manager (works out of the box for both wired and Wi-Fi). Gated on the master
# `itera.enable` with `mkDefault` values, so everything is opt-out and overridable.
#
# Also pins a *stable* (but still non-hardware) MAC address, opting out of the
# per-connection MAC randomization that the hardening layer (nix-mineral) turns
# on by default — that randomization hands the machine a fresh DHCP lease/IP on
# every reboot. See `stableMac.enable` below.
#
# Finally, runs systemd-resolved as a local caching DNS stub so repeat lookups
# don't re-query upstream — which keeps the machine under per-client DNS rate
# limits (e.g. Pi-hole's default 1000 queries/60s) on any network. See
# `resolved.enable` below.
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

    resolved.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Run systemd-resolved as a local caching DNS stub (127.0.0.53).
        NetworkManager hands it whatever DNS servers each network provides
        (DHCP, VPN, …) and resolved caches the answers, so repeat lookups
        during heavy activity — a large game download opening many connections
        is the textbook case — don't re-query upstream. This keeps the machine
        comfortably under per-client DNS rate limits (e.g. Pi-hole's default
        1000 queries / 60s) on *any* network, not just at home. Set to false to
        resolve directly against the network's DNS with no local cache.
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

    (mkIf cfg.resolved.enable {
      services.resolved.enable = mkDefault true;

      # Hand each network's DNS servers to resolved (which then owns
      # /etc/resolv.conf as the 127.0.0.53 stub) instead of NetworkManager
      # writing resolv.conf directly — that's what puts the cache in the path.
      networking.networkmanager.dns = mkDefault "systemd-resolved";

      # nix-mineral defaults resolved's DNSSEC to "true" (strict). It's inert
      # while resolved is off, but turning resolved on would activate it — and
      # strict DNSSEC breaks the very cases this cache exists to serve: split-
      # horizon/internal zones (a Pi-hole serving `*.mylocal` returns unsigned
      # answers) and captive-portal / hotel Wi-Fi that mangles DNSSEC. Opt out
      # so validation falls back to nixpkgs' default (off). Caching, not
      # validation, is the goal here.
      nix-mineral.settings.misc.dnssec = mkDefault false;

      # Avahi (enabled by the desktop battery) is already the mDNS/LLMNR
      # responder and sits ahead of resolved in nsswitch, so leave link-local
      # name resolution to it rather than having resolved fight Avahi for
      # UDP 5353.
      services.resolved.settings.Resolve = {
        MulticastDNS = mkDefault "false";
        LLMNR = mkDefault "false";
      };
    })
  ]);
}
