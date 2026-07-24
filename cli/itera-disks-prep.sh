# itera disks prep — wipe a disk blank so autoClaim will format and mount it.
#
# Packaged as `itera-disks-prep` (flake/cli.nix), reached via `itera disks prep`.
# `itera.disko.autoClaim` only ever claims a BLANK disk (no partition table, no
# filesystem) — it never touches a disk that holds data. This command is the
# deliberate way to hand it a disk that currently has data: it DESTROYS every
# signature and partition table on the target disk, making it blank, then (if the
# autoClaim service is installed) restarts it so the disk is claimed immediately
# instead of on the next boot.
#
# It is destructive, so it refuses the running system's disk outright and requires
# either an interactive confirmation (retype the device path) or `--yes`. The wipe
# needs root; it elevates with sudo when not already root.
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash. lsblk/wipefs/sgdisk come from runtimeInputs; sudo/systemctl
# resolve from the ambient PATH.

usage() {
  cat <<'EOF'
itera disks prep — wipe a disk blank so itera.disko.autoClaim will claim it.

Usage: itera disks prep [--yes] <device>

  <device>   Whole disk to wipe, e.g. /dev/sdb (NOT a partition like /dev/sdb1).
  --yes,-y   Skip the interactive confirmation (for scripted use).

DESTROYS all data on <device>. The running system's disk is always refused.
EOF
}

assume_yes=0
device=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y | --yes) assume_yes=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "itera disks prep: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$device" ]; then
        echo "itera disks prep: unexpected extra argument '$1'" >&2
        exit 1
      fi
      device="$1"
      ;;
  esac
  shift
done

if [ -z "$device" ]; then
  echo "itera disks prep: no device given." >&2
  usage >&2
  exit 1
fi

if [ ! -b "$device" ]; then
  echo "itera disks prep: '$device' is not a block device." >&2
  exit 1
fi

# Must be a whole disk, not a partition — autoClaim owns whole disks.
if [ "$(lsblk -dnro TYPE "$device" 2>/dev/null || true)" != "disk" ]; then
  echo "itera disks prep: '$device' is not a whole disk (a partition?). Pass the disk, e.g. /dev/sdb." >&2
  exit 1
fi

# Refuse the running system's disk. Any system mountpoint anywhere on the disk
# (root, boot, nix, persist) means we must never wipe it.
is_system_mount() {
  case "$1" in
    / | /boot | /boot/* | /nix | /persist) return 0 ;;
    *) return 1 ;;
  esac
}
while read -r mp; do
  if [ -n "$mp" ] && is_system_mount "$mp"; then
    echo "itera disks prep: refusing '$device' — it hosts the running system ($mp)." >&2
    exit 1
  fi
done < <(lsblk -nro MOUNTPOINT "$device" 2>/dev/null)

# Warn (but allow) if the disk could never be auto-claimed anyway.
tran="$(lsblk -dnro TRAN "$device" 2>/dev/null || true)"
rm="$(lsblk -dnro RM "$device" 2>/dev/null || echo 0)"
if [ "$tran" = "usb" ] || [ "$rm" = "1" ]; then
  echo "warning: '$device' is removable/USB — itera.disko.autoClaim only claims internal fixed disks," >&2
  echo "         so wiping it will not get it auto-claimed." >&2
fi

echo "About to DESTROY all data on $device:"
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$device" || true
echo

if [ "$assume_yes" -ne 1 ]; then
  if [ ! -r /dev/tty ]; then
    echo "itera disks prep: no terminal for confirmation — re-run with --yes to proceed." >&2
    exit 1
  fi
  printf "Type the device path (%s) to confirm the wipe: " "$device"
  read -r reply </dev/tty
  if [ "$reply" != "$device" ]; then
    echo "itera disks prep: confirmation did not match — aborting." >&2
    exit 1
  fi
fi

# The wipe needs root; elevate only if we are not already.
sudo_cmd=()
if [ "$(id -u)" -ne 0 ]; then sudo_cmd=(sudo); fi

echo "Wiping $device ..."
"${sudo_cmd[@]}" wipefs -a "$device"
"${sudo_cmd[@]}" sgdisk --zap-all "$device"
"${sudo_cmd[@]}" udevadm settle 2>/dev/null || true
echo "$device is now blank."

# Claim it now if the autoClaim service is installed, else explain when it happens.
if systemctl list-unit-files itera-claim-disks.service >/dev/null 2>&1 &&
  systemctl cat itera-claim-disks.service >/dev/null 2>&1; then
  echo "Restarting itera-claim-disks to claim it now ..."
  "${sudo_cmd[@]}" systemctl restart itera-claim-disks.service
  echo "Done. Check: systemctl status itera-claim-disks"
else
  echo "Enable itera.disko.autoClaim (and rebuild) to have itera format and mount it,"
  echo "or add it explicitly as an itera.disko.dataDrives entry."
fi
