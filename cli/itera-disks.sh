# itera disks — list internal fixed disks and the config to add them as data drives.
#
# Packaged as `itera-disks` (flake/cli.nix) and reached via `itera disks`. It is a
# read-only inspection command: it never touches a disk, only reports.
#
# For every internal, FIXED (non-removable) whole disk it prints a stable
# /dev/disk/by-id/ path, size, model, and current mount usage, plus a
# ready-to-paste `itera.disko.dataDrives.<name>` block. itera OWNS a data drive:
# enabling the entry WIPES the whole disk, then partitions, formats, and mounts it
# (and LUKS-encrypts it when itera.disko.encryption is on — see
# modules/nixos/core/disko.nix). So the running system's disk and anything already
# mounted are flagged, and only genuinely free disks get a suggested block.
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own. lsblk comes from runtimeInputs
# (util-linux); readlink/grep resolve from the host PATH, as facter-report.sh does.

if ! command -v lsblk >/dev/null 2>&1; then
  echo "itera disks: lsblk not found (nixpkgs#util-linux)." >&2
  exit 1
fi

# The most human-readable stable by-id symlink for a whole disk: prefer the
# model+serial ids (ata-/nvme-/scsi-/mmc-) over the opaque wwn-/eui. forms, but
# fall back to whatever exists. `readlink -f` resolves each link, so only ids
# pointing at the whole disk (not a -partN) match. Prints nothing when the disk
# has no by-id link at all.
best_by_id() {
  local dev="$1" link tgt best="" fallback=""
  for link in /dev/disk/by-id/*; do
    [ -e "$link" ] || continue
    tgt="$(readlink -f "$link")" || continue
    [ "$tgt" = "$dev" ] || continue
    case "${link##*/}" in
      wwn-* | *-eui.*) fallback="${fallback:-$link}" ;;
      *) best="${best:-$link}" ;;
    esac
  done
  printf '%s\n' "${best:-$fallback}"
}

# Every non-empty mountpoint across a whole disk (its partitions included), one
# per line. Empty when nothing on the disk is mounted.
disk_mounts() {
  lsblk -nro MOUNTPOINT "$1" 2>/dev/null | grep -v '^$' || true
}

# Mountpoints that mark a disk as the running system's boot/root disk, so we never
# suggest wiping it. `/boot/*` catches an ESP mounted at e.g. /boot/efi.
is_system_mount() {
  case "$1" in
    / | /boot | /boot/* | /nix | /persist) return 0 ;;
    *) return 1 ;;
  esac
}

echo "Internal fixed disks"
echo "===================="
echo
echo "Add a disk below as an itera.disko.dataDrives entry. itera OWNS the whole"
echo "disk: enabling the entry WIPES it, then partitions, formats, and mounts it"
echo "(and LUKS-encrypts it when itera.disko.encryption is on). Prefer the by-id"
echo "path for \`device\` so it survives kernel renaming; pick your own \`mountpoint\`."
echo "(Removable/USB drives are excluded — those automount via itera.storage.)"
echo

found=0
suggested=0
while read -r dev type; do
  [ "$type" = "disk" ] || continue
  case "$dev" in
    /dev/zram* | /dev/loop* | /dev/sr* | /dev/ram* | /dev/fd*) continue ;;
  esac

  # Internal + fixed only: skip removable, hot-pluggable, and USB-transport disks.
  rm="$(lsblk -dnro RM "$dev" 2>/dev/null || echo 0)"
  hotplug="$(lsblk -dnro HOTPLUG "$dev" 2>/dev/null || echo 0)"
  tran="$(lsblk -dnro TRAN "$dev" 2>/dev/null || true)"
  if [ "$rm" = "1" ] || [ "$hotplug" = "1" ] || [ "$tran" = "usb" ]; then
    continue
  fi
  found=1

  size="$(lsblk -dnro SIZE "$dev" 2>/dev/null || true)"
  # MODEL read WITHOUT -r (raw): raw mode escapes the spaces in a model name as
  # \x20. List mode keeps them readable; trim any trailing column padding.
  model="$(lsblk -dno MODEL "$dev" 2>/dev/null || true)"
  model="${model%"${model##*[![:space:]]}"}"
  byid="$(best_by_id "$dev")"

  # Current usage, and whether any of it is a system mount (→ this is the disk the
  # running system boots from, so it must not be offered as a data drive).
  mapfile -t mounts < <(disk_mounts "$dev")
  mounts_str=""
  system_disk=0
  for m in "${mounts[@]}"; do
    mounts_str+="${mounts_str:+, }$m"
    if is_system_mount "$m"; then system_disk=1; fi
  done

  printf '  %s  —  %s  %s\n' "$dev" "${model:-unknown model}" "${size:-?}"
  if [ -n "$byid" ]; then
    printf '    device (by-id):  %s\n' "$byid"
  else
    printf '    device (by-id):  (none found — falling back to the kernel name %s)\n' "$dev"
  fi
  if [ -z "$mounts_str" ]; then
    printf '    in use:          not mounted\n'
  else
    printf '    in use:          %s\n' "$mounts_str"
  fi

  if [ "$system_disk" = "1" ]; then
    printf '    >> This is your running system disk — do NOT add it as a data drive.\n\n'
    continue
  fi
  if [ -n "$mounts_str" ]; then
    printf '    >> Currently mounted — adding it as a data drive WIPES that data.\n'
  fi

  suggested=$((suggested + 1))
  attr="data"
  [ "$suggested" -gt 1 ] && attr="data$suggested"
  printf '    add as:\n'
  printf '      itera.disko.dataDrives.%s = {\n' "$attr"
  printf '        device = "%s";\n' "${byid:-$dev}"
  printf '        mountpoint = "/%s";   # <- choose where to mount it\n' "$attr"
  printf '      };\n\n'
done < <(lsblk -dpno NAME,TYPE 2>/dev/null)

if [ "$found" = "0" ]; then
  echo "  No internal fixed disks detected."
fi
