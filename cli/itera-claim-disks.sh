# itera-claim-disks — boot-time auto-claim of blank internal data disks.
#
# Backs `itera.disko.autoClaim` (modules/nixos/core/auto-claim-disks.nix): a
# oneshot systemd service runs this at boot (and can be re-run to pick up a disk
# added later — `systemctl restart itera-claim-disks`). For every INTERNAL, FIXED
# disk that is NOT the boot disk it does one of three things:
#
#   * already ours (carries a partition labelled `itera-claim`) → open/mount it;
#   * genuinely BLANK (no partition table, no filesystem/LUKS signature, no
#     partitions) → partition + format + mount it, marking it `itera-claim`;
#   * anything else (a foreign partition table or filesystem) → SKIP and log.
#
# That last rule is the safety contract: this service NEVER writes to a disk that
# holds existing data. To hand it a disk that currently has data, wipe it first
# with `itera disks prep <device>` (cli/itera-disks-prep.sh), which makes it blank.
#
# When itera.disko.encryption is on, claimed disks are LUKS-encrypted with an
# auto-generated keyfile (ITERA_CLAIM_KEYFILE) that lives on persistent storage —
# itself encrypted at rest by the boot disk — so unlocking a data disk is gated
# behind the boot unlock. No per-disk TPM2 enrollment; the keyfile is the key.
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own. Every tool it calls (lsblk,
# blkid, wipefs, sgdisk, mkfs.*, cryptsetup, systemd-mount, udevadm) comes from the
# service's runtimeInputs, since a systemd unit has a minimal ambient PATH.

: "${ITERA_CLAIM_FSTYPE:=btrfs}"
: "${ITERA_CLAIM_MOUNTBASE:=/mnt/itera}"
: "${ITERA_CLAIM_MOUNTOPTS:=}"
: "${ITERA_CLAIM_ENCRYPT:=0}"
: "${ITERA_CLAIM_KEYFILE:=/var/lib/itera/claim-disks.key}"

# The GPT partition label that marks a disk as itera-owned. Matched (not the
# by-partlabel symlink, which collides when several disks share a label) by
# scanning each disk's partitions, so it can be identical across disks.
readonly CLAIM_LABEL="itera-claim"

log() { echo "itera-claim-disks: $*"; }

# Mountpoints that mean "this is the running system's disk", so we never claim it.
is_system_mount() {
  case "$1" in
    / | /boot | /boot/* | /nix | /persist) return 0 ;;
    *) return 1 ;;
  esac
}

# A stable, human-readable id for a whole disk: the basename of a model+serial
# /dev/disk/by-id link (skipping the opaque wwn-/eui. forms), else the kernel name.
# Drives the mountpoint so it survives kernel renaming and reboots.
disk_id() {
  local dev="$1" link
  for link in /dev/disk/by-id/*; do
    [ -e "$link" ] || continue
    if [ "$(readlink -f "$link")" = "$dev" ]; then
      case "${link##*/}" in
        wwn-* | *-eui.*) continue ;;
        *)
          printf '%s\n' "${link##*/}"
          return 0
          ;;
      esac
    fi
  done
  printf '%s\n' "${dev##*/}"
}

# First partition of a whole disk as a full /dev path (line 2 of the lsblk tree;
# line 1 is the disk itself). Empty if the disk has no partitions.
first_partition() {
  local out
  out="$(lsblk -rpno NAME "$1" 2>/dev/null)" || true
  printf '%s\n' "$out" | sed -n '2p'
}

# True when a whole disk is safe to claim: no child partitions AND no on-disk
# signature by either probe. Conservative on purpose — any doubt means "not blank".
is_blank() {
  local dev="$1" kids
  kids="$(lsblk -rno NAME "$dev" 2>/dev/null | sed -n '2,$p')" || true
  [ -z "$kids" ] || return 1
  if blkid -p "$dev" >/dev/null 2>&1; then return 1; fi
  [ -z "$(wipefs -n "$dev" 2>/dev/null)" ] || return 1
  return 0
}

# Create the LUKS keyfile on first use (0400, on persistent storage). Idempotent.
ensure_keyfile() {
  if [ -s "$ITERA_CLAIM_KEYFILE" ]; then return 0; fi
  log "generating LUKS keyfile at $ITERA_CLAIM_KEYFILE"
  mkdir -p "$(dirname "$ITERA_CLAIM_KEYFILE")"
  (
    umask 077
    head -c 4096 /dev/urandom >"$ITERA_CLAIM_KEYFILE"
  )
  chmod 0400 "$ITERA_CLAIM_KEYFILE"
}

mkfs_fs() {
  case "$1" in
    btrfs) mkfs.btrfs -f "$2" >/dev/null ;;
    ext4) mkfs.ext4 -F "$2" >/dev/null ;;
    *)
      log "ERROR: unsupported fsType '$1'"
      return 1
      ;;
  esac
}

# Mount a formatted device at $mp via a transient systemd unit (so systemd tracks
# it and unmounts it cleanly on shutdown). Idempotent: a no-op if already mounted.
do_mount() {
  local dev="$1" mp="$2" fstype="$3" args
  if mountpoint -q "$mp"; then
    log "$mp already mounted"
    return 0
  fi
  mkdir -p "$mp"
  args=(--collect)
  [ -n "$fstype" ] && args+=(--type="$fstype")
  [ -n "$ITERA_CLAIM_MOUNTOPTS" ] && args+=(--options="$ITERA_CLAIM_MOUNTOPTS")
  if ! systemd-mount "${args[@]}" "$dev" "$mp"; then
    log "ERROR: failed to mount $dev at $mp"
    return 1
  fi
}

# The LUKS mapper name for a claimed partition (unique per partition).
mapper_for() { echo "itera-claim-$(basename "$1")"; }

# Re-attach an already-claimed partition: unlock it if it is a LUKS container, then
# mount it at the disk's deterministic mountpoint.
mount_claimed() {
  local dev="$1" part="$2" fsdev="$2" mapper fstype mp
  if [ "$(lsblk -dnro FSTYPE "$part" 2>/dev/null || true)" = "crypto_LUKS" ]; then
    ensure_keyfile
    mapper="$(mapper_for "$part")"
    if [ ! -e "/dev/mapper/$mapper" ]; then
      if ! cryptsetup luksOpen --key-file "$ITERA_CLAIM_KEYFILE" "$part" "$mapper"; then
        log "ERROR: could not unlock claimed disk $part (keyfile mismatch?)"
        return 1
      fi
    fi
    fsdev="/dev/mapper/$mapper"
  fi
  fstype="$(lsblk -dnro FSTYPE "$fsdev" 2>/dev/null || true)"
  mp="$ITERA_CLAIM_MOUNTBASE/$(disk_id "$dev")"
  do_mount "$fsdev" "$mp" "$fstype"
}

# Partition + format + mount a confirmed-blank disk, marking it itera-claim.
claim_blank() {
  local dev="$1" part fsdev mapper mp fstype="$ITERA_CLAIM_FSTYPE"
  log "claiming blank disk $dev (fsType=$fstype, encrypt=$ITERA_CLAIM_ENCRYPT)"
  sgdisk --zap-all "$dev" >/dev/null
  sgdisk --new=1:0:0 --change-name="1:$CLAIM_LABEL" "$dev" >/dev/null
  udevadm settle
  part="$(first_partition "$dev")"
  if [ -z "$part" ]; then
    log "ERROR: no partition appeared on $dev after partitioning"
    return 1
  fi
  fsdev="$part"
  if [ "$ITERA_CLAIM_ENCRYPT" = "1" ]; then
    ensure_keyfile
    mapper="$(mapper_for "$part")"
    if ! cryptsetup luksFormat --batch-mode --key-file "$ITERA_CLAIM_KEYFILE" "$part"; then
      log "ERROR: luksFormat failed on $part"
      return 1
    fi
    if ! cryptsetup luksOpen --key-file "$ITERA_CLAIM_KEYFILE" "$part" "$mapper"; then
      log "ERROR: luksOpen failed on $part"
      return 1
    fi
    fsdev="/dev/mapper/$mapper"
  fi
  mkfs_fs "$fstype" "$fsdev" || return 1
  mp="$ITERA_CLAIM_MOUNTBASE/$(disk_id "$dev")"
  do_mount "$fsdev" "$mp" "$fstype" || return 1
  log "claimed $dev -> $mp"
}

# Decide what to do with one candidate whole disk.
handle_disk() {
  local dev="$1" name label claimpart=""
  # Find an itera-claim partition on this disk, if any. Raw output so a foreign
  # partition label with spaces can't split across our two fields.
  while read -r name label; do
    [ "$label" = "$CLAIM_LABEL" ] && claimpart="$name"
  done < <(lsblk -rpno NAME,PARTLABEL "$dev" 2>/dev/null | sed -n '2,$p')

  if [ -n "$claimpart" ]; then
    mount_claimed "$dev" "$claimpart"
  elif is_blank "$dev"; then
    claim_blank "$dev"
  else
    log "skipping $dev — not blank and not itera-claimed (holds existing data)"
  fi
}

main() {
  mkdir -p "$ITERA_CLAIM_MOUNTBASE"
  udevadm settle 2>/dev/null || true

  while read -r dev type; do
    [ "$type" = "disk" ] || continue
    case "$dev" in
      /dev/zram* | /dev/loop* | /dev/sr* | /dev/ram* | /dev/fd* | /dev/md* | /dev/dm-*) continue ;;
    esac

    # Internal + fixed only: skip removable, hot-pluggable, and USB-transport disks.
    rm="$(lsblk -dnro RM "$dev" 2>/dev/null || echo 0)"
    hotplug="$(lsblk -dnro HOTPLUG "$dev" 2>/dev/null || echo 0)"
    tran="$(lsblk -dnro TRAN "$dev" 2>/dev/null || true)"
    if [ "$rm" = "1" ] || [ "$hotplug" = "1" ] || [ "$tran" = "usb" ]; then
      continue
    fi

    # Skip the running system's disk (the one carrying /, /boot, /nix, /persist).
    system=0
    while read -r mp; do
      if [ -n "$mp" ] && is_system_mount "$mp"; then system=1; fi
    done < <(lsblk -nro MOUNTPOINT "$dev" 2>/dev/null)
    [ "$system" = "1" ] && continue

    # Isolate each disk: a failure on one must not abort the rest (and running the
    # handler in a `|| ` context also suppresses `set -e` inside it, so a probe that
    # returns non-zero is handled by our explicit checks, not a hard exit).
    handle_disk "$dev" || log "ERROR: failed to claim/mount $dev — continuing"
  done < <(lsblk -dpno NAME,TYPE 2>/dev/null)
}

main
