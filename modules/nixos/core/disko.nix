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
# Full-disk encryption: opt in with `encryption.enable` to wrap the btrfs root AND
# (when present) the swap partition in LUKS, so everything at rest — `/`, `/nix`,
# `/persist`, and the hibernation image in swap — is encrypted. The ESP stays
# unencrypted (firmware must read it). It is opt-IN (default off, like
# `itera.secureBoot`) because it changes the on-disk format and demands a passphrase
# at every boot. Both containers are enrolled to the SAME passphrase, so at boot
# itera's systemd initrd caches the first entry and unlocks both with a SINGLE
# prompt; at install time disko's per-device `askPassword` prompts once per
# container (you type it for root and again for swap — a one-time cost). Set
# `encryption.passwordFile` to install non-interactively. Enabling encryption also
# auto-enables `itera.hardware.initrd.usbSupport` so a USB keyboard can type the
# passphrase in early boot (override it back to false on a laptop with a built-in
# keyboard). No key material lives on disk — the passphrase is in the LUKS header
# plus your memory — so nothing extra needs persisting under impermanence.
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
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) str bool nullOr;

  cfg = config.itera.disko;
  ec = cfg.encryption;

  mountOptions = [
    "compress=zstd"
    "noatime"
  ];

  # Wrap a partition's inner content in a disko LUKS container when encryption is
  # on; otherwise pass the content through untouched. The inner device becomes
  # `/dev/mapper/<name>`, and disko auto-emits the matching
  # `boot.initrd.luks.devices.<name>` entry (its `initrdUnlock`, on by default) so
  # boot-time unlock needs no manual wiring. A null `passwordFile` leaves disko's
  # `askPassword` default in force (interactive prompt when formatting).
  wrapLuks =
    name: inner:
    if ec.enable then
      {
        type = "luks";
        inherit name;
        settings = {
          inherit (ec) allowDiscards;
        };
        inherit (ec) passwordFile;
        content = inner;
      }
    else
      inner;
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
      default = cfg.swapSize != "";
      defaultText = lib.literalExpression ''config.itera.disko.swapSize != ""'';
      description = ''
        Register the swap partition as the hibernation resume device
        ({option}`boot.resumeDevice`), so {command}`systemctl hibernate` works out
        of the box. Gated on swap: it defaults to `true` exactly when a swap
        partition is declared ({option}`itera.disko.swapSize` set) and to `false`
        otherwise, so hibernation is never wired up without a real device to
        resume from. Set to `false` to create swap without wiring suspend-to-disk
        (e.g. swap purely for memory pressure), or when you drive
        {option}`boot.resumeDevice` yourself.
      '';
    };

    encryption = {
      enable = mkOption {
        type = bool;
        default = false;
        description = ''
          Encrypt the disk with LUKS: the btrfs root (carrying `/`, {file}`/nix`,
          and {file}`/persist`) and, when {option}`itera.disko.swapSize` is set, the
          swap partition too — so all data at rest, including the hibernation image,
          is encrypted. The ESP at {file}`/boot` stays unencrypted (firmware must
          read it).

          OFF by default (unlike most of itera): it changes the on-disk format and
          requires a passphrase at every boot. Both containers are enrolled to the
          same passphrase, so itera's systemd initrd unlocks both with a single
          prompt at boot. Enabling this also turns on
          {option}`itera.hardware.initrd.usbSupport` (via `mkDefault`) so a USB
          keyboard can type the passphrase in early boot; override it back to
          `false` on a laptop whose built-in keyboard already works in the initrd.
        '';
      };

      passwordFile = mkOption {
        type = nullOr str;
        default = null;
        example = "/tmp/luks.key";
        description = ''
          Path to a file whose contents become the LUKS passphrase when disko
          **formats** the disk (install time only — it is never stored in the
          system). `null` (the default) makes disko prompt interactively for a new
          passphrase while partitioning. Set this to install non-interactively
          (e.g. from an automated {command}`disko-install`). Has no effect once the
          disk is formatted; the passphrase then lives only in the LUKS header.
        '';
      };

      allowDiscards = mkOption {
        type = bool;
        default = true;
        description = ''
          Pass {command}`discard`/TRIM through the LUKS mapping to the underlying
          SSD, preserving its performance and wear-levelling. This has a small
          confidentiality tradeoff — the pattern of used vs. free blocks becomes
          observable on the raw device — so set it to `false` on maximum-paranoia
          hosts to keep the encrypted device fully opaque at the cost of TRIM.
        '';
      };
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.device != "";
        message = "itera.disko.enable is set but itera.disko.device is empty — set it to the target disk (e.g. \"/dev/nvme0n1\").";
      }
    ];

    # With encryption on, the LUKS passphrase is typed in the initrd — which needs
    # USB HID modules present for a USB keyboard to work. `mkDefault` so it's on
    # whenever encryption is on, while a laptop whose built-in keyboard already
    # works in the initrd can set it back to false to avoid the USB-in-stage-1
    # stall the hardware battery warns about.
    itera.hardware.initrd.usbSupport = mkIf ec.enable (mkDefault true);

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
            # Wrapped in LUKS when encryption is on (mapper `/dev/mapper/cryptswap`),
            # so the hibernation image written here is encrypted. The swap type's
            # `resumeDevice` then resolves to the mapper, so `boot.resumeDevice`
            # points at the decrypted device and hibernation still works.
            content = wrapLuks "cryptswap" {
              type = "swap";
              discardPolicy = "both";
              # Register this partition as the hibernation resume target. disko sets
              # `boot.resumeDevice` to the (decrypted, when encrypted) device and
              # adds it to `swapDevices`; itera's systemd initrd then emits the
              # `resume=` kernel param from it. Gated on `resume` so swap can exist
              # without wiring suspend-to-disk.
              resumeDevice = cfg.resume;
            };
          };

          root = {
            size = "100%";
            # Wrapped in LUKS when encryption is on (mapper `/dev/mapper/cryptroot`);
            # the btrfs and its `/`, `/nix`, `/persist` subvolumes then live inside
            # the encrypted container, unlocked in the initrd before they mount.
            content = wrapLuks "cryptroot" {
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
