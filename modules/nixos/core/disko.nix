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
# Hibernation: set `swapSize` to at least the machine's RAM and the resulting swap
# partition doubles as the suspend-to-disk resume target — disko wires
# `boot.resumeDevice` to it (via `resume`, on by default) and, with itera's
# systemd initrd, that alone makes `systemctl hibernate` work. The tmpfs root from
# `itera.impermanence` is no obstacle: hibernation snapshots ALL of RAM (including
# the tmpfs `/`) to swap and restores it verbatim on resume. itera's in-RAM zram
# swap (`itera.hardware`) cannot be a hibernation target, which is why a real,
# disk-backed swap partition is what enables it. Hosts with no swap partition are
# unaffected — `resume` is inert unless a swap partition exists.
#
# Opt-OUT: on automatically with `itera.enable`, gated on
# `itera.enable && cfg.enable` with `mkDefault` opinionated values. Because
# partitioning is destructive and has no sensible default target, `device` MUST
# be set — the assertion below fails the build otherwise, so a host either points
# disko at a disk or sets `itera.disko.enable = false`.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) str bool;

  cfg = config.itera.disko;

  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  options.itera.disko = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Whether to declare itera's disk layout (disko). On by default whenever
        {option}`itera.enable` is set; requires {option}`itera.disko.device`.
        Set to `false` to manage partitioning yourself.
      '';
    };

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

        For hibernation (suspend-to-disk) the swap partition must be at least the
        size of RAM — the compressed image usually fits in RAM-sized swap, but
        RAM-sized is the safe rule. Setting this to `>= RAM` enables
        {command}`systemctl hibernate` automatically via {option}`itera.disko.resume`.
      '';
    };

    resume = mkOption {
      type = bool;
      default = true;
      description = ''
        When a swap partition is declared ({option}`itera.disko.swapSize` set),
        also register it as the hibernation resume device
        ({option}`boot.resumeDevice`), so {command}`systemctl hibernate` works out
        of the box. On by default; inert when no swap partition exists. Set to
        `false` to create swap without wiring suspend-to-disk (e.g. swap purely for
        memory pressure), or when you drive {option}`boot.resumeDevice` yourself.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
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
              # Register this partition as the hibernation resume target. disko sets
              # `boot.resumeDevice` to the partition's stable by-partlabel path and
              # adds it to `swapDevices`; itera's systemd initrd then emits the
              # `resume=` kernel param from it. Gated on `resume` so swap can exist
              # without wiring suspend-to-disk.
              resumeDevice = cfg.resume;
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
