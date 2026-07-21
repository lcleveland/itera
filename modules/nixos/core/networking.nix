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
#
# Finally, an *opt-in* workaround (`r8169Workaround`) for a hardware bug in
# Realtek 2.5GbE NICs on the in-tree `r8169` driver, which silently wedge under
# sustained saturation (a large game download is the classic trigger) with
# nothing logged. See `r8169Workaround.enable` below.
{
  config,
  lib,
  pkgs,
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

    r8169Workaround.enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Work around silent link stalls on Realtek 2.5GbE NICs (RTL812x /
        RTL8126, in-tree `r8169` driver) that wedge under sustained saturation —
        a large Steam/game download is the classic trigger — while the link
        still reads "up" and nothing is logged. Enabling this:

        - disables PCIe ASPM globally via the `pcie_aspm=off` kernel parameter
          (the power-management transition is the usual culprit), and
        - turns off Energy-Efficient Ethernet (EEE) on every `r8169`-driven
          interface at boot.

        Opt-in and off by default: it only matters on affected hardware, carries
        a small idle-power cost, and the `pcie_aspm=off` parameter is global. A
        host with such a NIC sets this to true (a reboot is required for the
        kernel parameter to take effect).
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

    (mkIf cfg.r8169Workaround.enable {
      # PCIe ASPM (its L1 power-state transition in particular) is the usual
      # cause of the r8169 stall, so switch it off system-wide. This is a
      # kernel parameter, so it only takes effect after a reboot.
      boot.kernelParams = [ "pcie_aspm=off" ];

      # Disable Energy-Efficient Ethernet on every r8169 NIC at boot. Driven off
      # the driver name (not a hard-coded interface) so it applies to whichever
      # interface the affected card comes up as. Resolving names at runtime also
      # dodges the udev link-rename race.
      systemd.services.itera-r8169-disable-eee = {
        description = "Disable EEE on r8169 NICs (stall workaround)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-pre.target" ];
        path = [
          pkgs.coreutils
          pkgs.ethtool
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for dev in /sys/class/net/*; do
            [ -e "$dev/device/driver" ] || continue
            case "$(readlink -f "$dev/device/driver")" in
              */r8169) ethtool --set-eee "''${dev##*/}" eee off || true ;;
            esac
          done
        '';
      };
    })
  ]);
}
