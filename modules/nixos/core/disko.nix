# itera's declarative disk-partitioning battery.
#
# A thin, opinionated wrapper over disko (bundled by `modules/nixos/default.nix`).
# Enabling `itera.disko` + pointing it at a device produces a complete, bootable
# GPT layout: an ESP plus a single btrfs partition carrying `/`, `/nix`, and
# `/persist` subvolumes. That subvolume split is exactly what an impermanence
# setup wants — see `itera.impermanence`, which forces `/` onto tmpfs and leaves
# the btrfs `/nix` + `/persist` in place — but the layout also boots perfectly
# well on its own.
#
# Follows itera's module conventions (`mkEnableOption`, `mkIf cfg.enable`,
# `mkDefault` for opinionated values). Config is gated on this feature's own
# `enable` rather than the global `itera.enable`: partitioning is foundational and
# destructive, so silently no-op'ing it would be a footgun.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) str;

  cfg = config.itera.disko;

  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  options.itera.disko = {
    enable = mkEnableOption "itera's declarative disk layout (disko)";

    device = mkOption {
      type = str;
      default = "";
      example = "/dev/nvme0n1";
      description = ''
        The whole-disk device to partition. Required when {option}`itera.disko.enable`
        is set. Everything on this device is destroyed when disko formats it.
      '';
    };

    espSize = mkOption {
      type = str;
      default = "1G";
      description = "Size of the EFI System Partition mounted at {file}`/boot`.";
    };

    swapSize = mkOption {
      type = str;
      default = "";
      example = "8G";
      description = ''
        Size of an optional swap partition. Empty (the default) creates no swap.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.device != "";
        message = "itera.disko.enable is set but itera.disko.device is empty — set it to the target disk (e.g. \"/dev/nvme0n1\").";
      }
    ];

    disko.devices.disk.main = {
      inherit (cfg) device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = cfg.espSize;
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          swap = mkIf (cfg.swapSize != "") {
            size = cfg.swapSize;
            content = {
              type = "swap";
              discardPolicy = "both";
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = {
                  inherit mountOptions;
                  mountpoint = "/";
                };
                "/nix" = {
                  inherit mountOptions;
                  mountpoint = "/nix";
                };
                "/persist" = {
                  inherit mountOptions;
                  mountpoint = "/persist";
                };
              };
            };
          };
        };
      };
    };
  };
}
