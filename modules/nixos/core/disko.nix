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
# at every boot. Every container (root, swap, and each data drive — see below) is
# enrolled to the SAME passphrase, so at boot itera's systemd initrd caches the
# first entry and unlocks them all with a SINGLE prompt; at install time disko's
# per-device `askPassword` prompts once per container (a one-time cost). Set
# `encryption.passwordFile` to install non-interactively. Enabling encryption also
# auto-enables `itera.hardware.initrd.usbSupport` so a USB keyboard can type the
# passphrase in early boot (override it back to false on a laptop with a built-in
# keyboard). No key material lives on disk — the passphrase is in the LUKS header
# plus your memory — so nothing extra needs persisting under impermanence.
#
# Extra data drives: `dataDrives` declares additional internal fixed disks that
# itera OWNS — it partitions, formats (btrfs or ext4), and mounts each whole disk,
# and, crucially, wraps each in LUKS whenever `encryption.enable` is on so a data
# drive is encrypted and unlocked by exactly the same single-passphrase/TPM2 flow
# as the boot disk (that uniform encryption is the whole reason itera owns them
# rather than just mounting a pre-existing filesystem). They are independent
# persistent mounts, NOT `neededForBoot`: they unlock in the initrd but mount in
# stage 2, so they compose with the `itera.impermanence` tmpfs root without touching
# `/`, `/nix`, or `/persist`. Empty by default (a no-op).
#
# TPM2 auto-unlock: layer `encryption.tpm2.enable` on top to unseal the containers
# from the machine's TPM2 with no passphrase on a trusted boot. A TPM2 keyslot is
# enrolled into each LUKS header (sealed to `encryption.tpm2.pcrs`, default PCR 7 =
# Secure Boot state) and the initrd gets `tpm2-device=auto`; the passphrase stays as
# a recovery fallback if the sealed PCR state changes. Enrollment binds to the live
# TPM, so it runs on the target machine: itera's installer does it automatically at
# install (needs `encryption.passwordFile`), else run `itera-tpm2-enroll` once. Its
# real security depends on `itera.secureBoot` — without it, TPM unlock stops a pulled
# disk being read but not a thief booting the machine. `usbSupport` stays force-on
# even under TPM2 so the recovery-passphrase fallback remains typable on a USB
# keyboard (the happy path types nothing, but a PCR change drops you to the prompt).
#
# Opt-OUT: on automatically with `itera.enable`, gated on
# `itera.enable && cfg.enable` with `mkDefault` opinionated values. Because
# partitioning is destructive and has no sensible default target, `device` MUST
# be set — the assertion below fails the build otherwise, so a host either points
# disko at a disk or sets `itera.disko.enable = false`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    str
    bool
    nullOr
    attrsOf
    submodule
    listOf
    enum
    ;

  cfg = config.itera.disko;
  ec = cfg.encryption;
  tpm = ec.tpm2;

  # Underlying raw partition (by disko partlabel) for a given disko disk +
  # partition name — the device systemd-cryptenroll writes TPM2 tokens into. It
  # operates on the LUKS header, so the raw partition (not the /dev/mapper device)
  # is the target. disko always names partitions `disk-<diskname>-<partname>`, so
  # this generalizes over any disk (the boot disk "main" AND each data drive).
  cryptPartition = disk: part: "/dev/disk/by-partlabel/disk-${disk}-${part}";

  # The LUKS mapper name for a data drive. The `cryptdata-` prefix can never
  # collide with `cryptroot`/`cryptswap`, so any drive attr name (even "root" or
  # "swap") is safe.
  dataMapper = name: "cryptdata-${name}";

  # Every LUKS container wrapLuks creates, mapped to its underlying raw partition.
  # Contains ONLY present containers: `cryptroot` always, `cryptswap` when a swap
  # partition is declared, and one `cryptdata-<name>` per data drive. Enrollment
  # and crypttab wiring iterate this set (all gated on encryption being on).
  luksContainers = {
    cryptroot = cryptPartition "main" "root";
  }
  // lib.optionalAttrs (cfg.swapSize != "") { cryptswap = cryptPartition "main" "swap"; }
  // lib.mapAttrs' (
    name: _: lib.nameValuePair (dataMapper name) (cryptPartition name "data")
  ) cfg.dataDrives;

  # A helper that (re-)enrolls every present LUKS container's TPM2 keyslot against
  # the configured PCRs. `--wipe-slot=tpm2` first makes it idempotent and lets it
  # rebind after a PCR change. Prompts once per device for an existing passphrase
  # unless `--unlock-key-file=…` is passed. Shipped for non-itera installers and for
  # re-enrolling after firmware/Secure-Boot changes; the itera installer runs the
  # same enrollment automatically at install time so the first boot needs no prompt.
  enrollScript = pkgs.writeShellApplication {
    name = "itera-tpm2-enroll";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      # Rebind the TPM2 keyslot on every itera LUKS container (root, swap, and any
      # data drives). Pass through any extra args (e.g. --unlock-key-file=/path) to
      # every invocation.
      for dev in ${lib.escapeShellArgs (lib.attrValues luksContainers)}; do
        echo "Enrolling TPM2 (PCRs ${tpm.pcrs}) into $dev" >&2
        systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto \
          --tpm2-pcrs=${lib.escapeShellArg tpm.pcrs} "$@" "$dev"
      done
    '';
  };

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

  # The disko partition `content` for a data drive: a flat filesystem (no
  # subvolumes — unlike the boot disk's btrfs root) mounted directly at the
  # drive's `mountpoint`, wrapped in LUKS when encryption is on. btrfs uses the
  # dedicated `btrfs` type with `-f` to force-format over any existing signature
  # (as the root does); ext4 uses the generic `filesystem`/`format` pair. A
  # `label` maps to `-L` for both. mountOptions default per fsType (see the option
  # below) because `compress=zstd` is btrfs-only and would break an ext4 mount.
  mkDataContent =
    name: drive:
    wrapLuks (dataMapper name) (
      if drive.fsType == "btrfs" then
        {
          type = "btrfs";
          extraArgs = [
            "-f"
          ]
          ++ lib.optionals (drive.label != null) [
            "-L"
            drive.label
          ];
          inherit (drive) mountpoint mountOptions;
        }
      else
        {
          type = "filesystem";
          format = drive.fsType;
          inherit (drive) mountpoint mountOptions;
        }
        // lib.optionalAttrs (drive.label != null) {
          extraArgs = [
            "-L"
            drive.label
          ];
        }
    );
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

      tpm2 = {
        enable = mkOption {
          type = bool;
          default = false;
          description = ''
            Auto-unlock the LUKS containers from the machine's TPM2 instead of
            typing the passphrase at every boot. A TPM2 keyslot is enrolled into
            each container's LUKS header (sealed to the {option}`itera.disko.encryption.tpm2.pcrs`
            PCR state) and itera's systemd initrd adds `tpm2-device=auto` to the
            crypttab, so a trusted boot unseals the volume key with no prompt.

            The passphrase keyslot is **kept** as a recovery fallback: if the sealed
            PCR state changes (firmware update, Secure Boot toggled, keys re-enrolled)
            the TPM refuses to release the key and boot falls back to prompting for
            the passphrase — after which you re-run {command}`itera-tpm2-enroll` to
            rebind.

            Enrollment binds to the live TPM + PCRs, so it must run on the target
            machine. itera's installer does it automatically at install time (needs
            {option}`itera.disko.encryption.passwordFile` set so it can unlock
            non-interactively); otherwise run {command}`sudo itera-tpm2-enroll` once
            after install. No key material is written to disk — the sealed secret
            lives in the TPM and the LUKS header.

            SECURITY: the strength of TPM auto-unlock depends on the PCRs binding to a
            trusted boot chain. With the default PCR 7 and {option}`itera.secureBoot`
            enabled, the disk only unseals under a verified Secure Boot state. WITHOUT
            Secure Boot, TPM unlock still stops the disk being read after it is removed
            from the machine, but does NOT stop a thief who simply powers the machine
            on — for that, enable {option}`itera.secureBoot` too.

            {option}`itera.hardware.initrd.usbSupport` stays force-enabled (via
            `mkDefault`) even with TPM2 on: the happy path types no passphrase, but
            the recovery-passphrase fallback (fired when the sealed PCR state
            changes) still needs a keyboard in early boot, and on machines whose
            built-in keyboard is USB-internal dropping it would lock you out of that
            prompt. A host that never needs USB in stage 1 can still set it `false`.
          '';
        };

        pcrs = mkOption {
          type = str;
          default = "7";
          example = "0+2+7";
          description = ''
            TPM2 PCRs the keyslot is sealed against, in {command}`systemd-cryptenroll`
            `--tpm2-pcrs=` syntax (`+`-separated). The default `"7"` binds to the
            Secure Boot state alone: it survives kernel/initrd updates (unlike PCR
            4/8/9/11) so it rarely needs re-enrollment, while refusing to unseal if
            Secure Boot is disabled or its keys change. Add firmware PCR 0 (`"0+7"`)
            for a stricter policy at the cost of re-enrolling after every firmware
            update. Changing this requires re-running {command}`itera-tpm2-enroll`.
          '';
        };
      };
    };

    dataDrives = mkOption {
      type = attrsOf (
        submodule (
          { name, ... }:
          {
            options = {
              device = mkOption {
                type = str;
                example = "/dev/sdb";
                description = ''
                  The whole-disk device for this data drive. Required, and DESTRUCTIVE:
                  itera owns the entire disk (a single-partition GPT) so that encryption
                  can be applied uniformly — everything on it is destroyed when disko
                  formats it. Point it at a fixed internal disk, not removable media
                  (use {option}`itera.storage` for USB drives).
                '';
              };

              fsType = mkOption {
                type = enum [
                  "btrfs"
                  "ext4"
                ];
                default = "btrfs";
                description = ''
                  Filesystem to create on the drive: `btrfs` (the default, matching
                  itera's root layout, formatted with `compress=zstd,noatime`) or `ext4`.
                '';
              };

              mountpoint = mkOption {
                type = str;
                example = "/data";
                description = ''
                  Absolute path this drive's filesystem mounts at. Required. Keep it
                  clear of the boot disk's mountpoints ({file}`/`, {file}`/nix`,
                  {file}`/persist`, {file}`/boot`); a data drive is an independent
                  persistent mount, not part of the impermanence root.
                '';
              };

              mountOptions = mkOption {
                type = listOf str;
                default =
                  if config.itera.disko.dataDrives.${name}.fsType == "btrfs" then
                    [
                      "compress=zstd"
                      "noatime"
                    ]
                  else
                    [ "noatime" ];
                defaultText = lib.literalExpression ''btrfs: [ "compress=zstd" "noatime" ]; ext4: [ "noatime" ]'';
                description = ''
                  Mount options for this drive. The default diverges by
                  {option}`fsType` because `compress=zstd` is btrfs-only and would
                  break an ext4 mount.
                '';
              };

              label = mkOption {
                type = nullOr str;
                default = null;
                example = "data";
                description = "Optional filesystem label (`-L`) for the drive.";
              };
            };
          }
        )
      );
      default = { };
      example = lib.literalExpression ''
        { data = { device = "/dev/sdb"; mountpoint = "/data"; }; }
      '';
      description = ''
        Additional internal fixed data drives that itera partitions, formats,
        mounts, and — when {option}`itera.disko.encryption.enable` is set —
        LUKS-encrypts with the SAME passphrase and TPM2 auto-unlock flow as the boot
        disk. Each attr becomes a whole-disk, single-partition GPT disk (DESTRUCTIVE),
        and the attr name is used as the disko disk name and the partlabel base
        (`disk-<name>-data`) — so keep it short (the GPT partlabel `disk-<name>-data`
        caps at 36 chars, i.e. name <= 26) and never `"main"` (that is the boot disk).

        Empty (the default) is a no-op. Data drives are independent persistent mounts
        (not `neededForBoot`): under {option}`itera.impermanence` they are unaffected
        by the tmpfs root, unlocking in the initrd but mounting in stage 2.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.device != "";
        message = "itera.disko.enable is set but itera.disko.device is empty — set it to the target disk (e.g. \"/dev/nvme0n1\").";
      }
    ]
    # Per-data-drive sanity checks. The attr name is reused as the disko disk name
    # and partlabel base, so guard the collisions and limits that would otherwise
    # surface as opaque disko/GPT errors much later.
    ++ lib.mapAttrsToList (name: drive: {
      assertion = drive.device != "";
      message = "itera.disko.dataDrives.${name}.device is empty — set it to the target disk (e.g. \"/dev/sdb\").";
    }) cfg.dataDrives
    ++ lib.mapAttrsToList (name: drive: {
      assertion = lib.hasPrefix "/" drive.mountpoint;
      message = "itera.disko.dataDrives.${name}.mountpoint must be an absolute path (e.g. \"/data\").";
    }) cfg.dataDrives
    ++ lib.mapAttrsToList (name: _: {
      assertion = name != "main";
      message = "itera.disko.dataDrives.\"main\" collides with the boot disk — rename it.";
    }) cfg.dataDrives
    ++ lib.mapAttrsToList (name: _: {
      assertion = builtins.stringLength "disk-${name}-data" <= 36;
      message = "itera.disko.dataDrives.${name}: GPT partlabel \"disk-${name}-data\" exceeds 36 chars — use a shorter attr name (<= 26).";
    }) cfg.dataDrives;

    # With encryption on, a LUKS passphrase may be typed in the initrd — which
    # needs USB HID modules present for a USB keyboard to work. `mkDefault` so it's
    # on whenever encryption is on, while a machine whose built-in keyboard already
    # works in the initrd can set it back to false to avoid the USB-in-stage-1
    # stall the hardware battery warns about. This stays on even under TPM2
    # auto-unlock: the happy path types nothing, but the recovery-passphrase
    # fallback (fired whenever the sealed PCR state changes — a firmware update,
    # Secure Boot toggle, or key re-enrollment) still needs a typable keyboard, and
    # on laptops whose built-in keyboard is USB-internal (e.g. Framework) dropping
    # this would leave that prompt with no keyboard — a lockout footgun. A host that
    # genuinely never needs USB in stage 1 can still set it back to false.
    itera.hardware.initrd.usbSupport = mkIf ec.enable (mkDefault true);

    # TPM2 auto-unlock. disko already emits a `boot.initrd.luks.devices.<name>` entry
    # per container (root, swap, and each data drive); we augment every one with
    # `tpm2-device=auto` so the systemd initrd unseals the volume key from the TPM
    # (falling back to the passphrase prompt when the sealed PCR state no longer
    # matches). The TPM kernel modules must be in the initrd for the device node to
    # exist in stage 1 (`boot.initrd.systemd.tpm2.enable` — default true under
    # systemd initrd — pulls in the tpm2-tss userspace). The enroll helper is shipped
    # for manual/rebind use. `luksContainers` already holds only the present
    # containers keyed by mapper name, so map over it directly.
    boot.initrd.luks.devices = mkIf (ec.enable && tpm.enable) (
      lib.mapAttrs (_: _: { crypttabExtraOpts = [ "tpm2-device=auto" ]; }) luksContainers
    );
    boot.initrd.availableKernelModules = mkIf (ec.enable && tpm.enable) [
      "tpm"
      "tpm_tis"
      "tpm_crb"
    ];
    environment.systemPackages = mkIf (ec.enable && tpm.enable) [ enrollScript ];

    # The boot disk (`main`) plus one whole-disk GPT per data drive. disko happily
    # manages many `disk.*` entries; NixOS mounts the resulting filesystems in
    # mountpoint-path order, so the boot disk's `/`, `/nix`, `/persist`, `/boot` and
    # each data drive's mountpoint all order correctly regardless of disk. Data
    # drives contribute nothing when `dataDrives` is empty (the default).
    disko.devices.disk = {
      main = {
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
    }
    // lib.mapAttrs (name: drive: {
      inherit (drive) device;
      type = "disk";
      content = {
        type = "gpt";
        # A single 100% partition carrying the drive's filesystem, wrapped in LUKS
        # (mapper `cryptdata-<name>`) when encryption is on so it joins the boot
        # disk's single-passphrase + TPM2 unlock. The partlabel is `disk-<name>-data`.
        partitions.data = {
          size = "100%";
          content = mkDataContent name drive;
        };
      };
    }) cfg.dataDrives;
  };
}
