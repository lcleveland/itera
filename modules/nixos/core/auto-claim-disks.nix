# itera's auto-claim battery: grab every blank internal data disk at boot.
#
# OPT-IN (default off, unlike most of itera): enabling `itera.disko.autoClaim`
# installs a boot-time oneshot service (cli/itera-claim-disks.sh) that finds every
# INTERNAL, FIXED disk which is NOT the boot disk and, for each one, either mounts
# it (if itera already claimed it) or — only when it is genuinely BLANK — partitions,
# formats, and mounts it. A disk that already holds a foreign partition table or
# filesystem is left untouched; to feed such a disk to the service, wipe it first
# with `itera disks prep <device>`. It is opt-in and gated on a blank check because
# it writes to whole disks — the exact opposite of a safe default.
#
# This is the RUNTIME counterpart to `itera.disko.dataDrives` (disko.nix), which
# claims named disks declaratively at install time. autoClaim needs no disk list
# and picks up disks added after install (re-run with
# `systemctl restart itera-claim-disks`, which `itera disks prep` does for you), at
# the cost of being an imperative boot-time service rather than part of the disko
# layout. The two compose: dataDrives-managed disks carry their own `disk-<name>-data`
# partlabels, not `itera-claim`, so autoClaim never double-claims them, and the boot
# disk is excluded by its live mountpoints (/, /boot, /nix, /persist).
#
# Encryption follows `itera.disko.encryption`: when it is on, claimed disks are
# LUKS-encrypted with an auto-generated keyfile kept on persistent storage (under
# the impermanence persistRoot when impermanence is on, so it is itself encrypted at
# rest by the boot disk). Unlocking a data disk is therefore gated behind the boot
# unlock; there is no separate per-disk TPM2 enrollment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types)
    bool
    str
    enum
    listOf
    ;

  cfg = config.itera.disko.autoClaim;
  ec = config.itera.disko.encryption;
  imp = config.itera.impermanence;

  # Keyfile home: directly on the persistent root under impermanence (a real,
  # disk-backed, boot-disk-encrypted filesystem — no bind-mount declaration needed),
  # else the ordinary persistent /var/lib on a non-impermanence host.
  keyFile =
    if imp.enable then "${imp.persistRoot}/itera/claim-disks.key" else "/var/lib/itera/claim-disks.key";

  claimScript = pkgs.writeShellApplication {
    name = "itera-claim-disks";
    # A systemd unit has a minimal ambient PATH, so every tool the script calls must
    # be carried here explicitly.
    runtimeInputs = [
      pkgs.util-linux # lsblk, blkid, wipefs, mountpoint
      pkgs.gptfdisk # sgdisk
      pkgs.btrfs-progs # mkfs.btrfs
      pkgs.e2fsprogs # mkfs.ext4
      pkgs.cryptsetup # LUKS
      pkgs.systemd # systemd-mount, udevadm
      pkgs.coreutils
    ];
    text = builtins.readFile ../../../cli/itera-claim-disks.sh;
  };
in
{
  options.itera.disko.autoClaim = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Automatically claim every blank internal fixed disk that is not the boot
        disk: at boot, itera partitions, formats, and mounts each such disk (and
        LUKS-encrypts it when {option}`itera.disko.encryption.enable` is set).

        OFF by default and blank-only by design — it writes to whole disks. A disk
        that already holds a partition table or filesystem is skipped, not wiped; run
        {command}`itera disks prep <device>` to blank a disk you want claimed. Disks
        added after boot are picked up on the next boot, or immediately with
        {command}`sudo systemctl restart itera-claim-disks`.
      '';
    };

    fsType = mkOption {
      type = enum [
        "btrfs"
        "ext4"
      ];
      default = "btrfs";
      description = "Filesystem created on each claimed disk (`btrfs` or `ext4`).";
    };

    mountBase = mkOption {
      type = str;
      default = "/mnt/itera";
      description = ''
        Directory under which claimed disks are mounted. Each disk mounts at
        {file}`<mountBase>/<disk-id>`, where `<disk-id>` is the disk's stable
        /dev/disk/by-id name, so a disk keeps its mountpoint across reboots and
        kernel renaming.
      '';
    };

    mountOptions = mkOption {
      type = listOf str;
      default =
        if cfg.fsType == "btrfs" then
          [
            "compress=zstd"
            "noatime"
          ]
        else
          [ "noatime" ];
      defaultText = lib.literalExpression ''btrfs: [ "compress=zstd" "noatime" ]; ext4: [ "noatime" ]'';
      description = ''
        Mount options for claimed disks. The default diverges by {option}`fsType`
        because `compress=zstd` is btrfs-only and would break an ext4 mount.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    systemd.services.itera-claim-disks = {
      description = "Claim and mount blank internal data disks (itera.disko.autoClaim)";
      wantedBy = [ "multi-user.target" ];
      # Needs the persistent root mounted (the LUKS keyfile lives there) and udev to
      # have populated the block devices; the script also runs `udevadm settle`.
      after = [ "local-fs.target" ];
      # A oneshot that stays "active" after it exits, so the claimed mounts count as
      # part of the unit's lifetime; `systemctl restart` re-runs it to pick up a
      # newly-added disk.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe claimScript;
      };
      environment = {
        ITERA_CLAIM_FSTYPE = cfg.fsType;
        ITERA_CLAIM_MOUNTBASE = cfg.mountBase;
        ITERA_CLAIM_MOUNTOPTS = lib.concatStringsSep "," cfg.mountOptions;
        ITERA_CLAIM_ENCRYPT = if ec.enable then "1" else "0";
        ITERA_CLAIM_KEYFILE = keyFile;
      };
    };
  };
}
