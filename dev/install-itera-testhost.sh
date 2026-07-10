# Interactive installer for itera's `itera-testhost`, meant to be run from a
# booted NixOS live ISO. It lists the machine's whole disks, lets you pick one,
# confirms the (destructive) wipe, then hands off to disko-install — saving you
# from spelling out the flake ref, config name, and `--disk main <device>` by
# hand.
#
# Wired up as the flake package `install-itera-testhost` in `flake/test-host.nix`.
# Usage (from the live ISO, as root):
#
#   nix run 'github:lcleveland/itera#install-itera-testhost'                 # pick from a menu
#   nix run 'github:lcleveland/itera#install-itera-testhost' -- /dev/nvme0n1 # skip the menu
#
# Any extra arguments after the device are forwarded to disko-install. Override
# the flake it installs from (e.g. a local clone) with the ITERA_INSTALL_FLAKE
# environment variable, remembering to keep it in root's env:
#
#   sudo -E ITERA_INSTALL_FLAKE=. nix run '.#install-itera-testhost'
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own.

FLAKE="${ITERA_INSTALL_FLAKE:-github:lcleveland/itera}"
CONFIG="itera-testhost"
DISK_NAME="main"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root — this partitions and installs to a disk." >&2
  echo "       re-run under sudo, e.g. 'sudo -E nix run <flake>#install-itera-testhost'." >&2
  exit 1
fi

# Optional non-interactive target: the first non-flag argument is the device.
# Anything after it is forwarded to disko-install untouched.
device=""
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  device="$1"
  shift
fi

if [ -z "$device" ]; then
  # Collect whole disks only (TYPE=disk excludes partitions, loop and CD-ROM
  # devices). `model` soaks up the rest of the line, so spaces in it are fine.
  names=()
  labels=()
  while read -r name type size model; do
    [ "$type" = "disk" ] || continue
    # zram/ram are RAM-backed block devices that report TYPE=disk but are never
    # valid install targets — drop them so they can't be picked by accident.
    case "$name" in
      /dev/zram* | /dev/ram*) continue ;;
    esac
    names+=("$name")
    labels+=("$name  ($size)  ${model:-unknown model}")
  done < <(lsblk -dpno NAME,TYPE,SIZE,MODEL)

  if [ "${#names[@]}" -eq 0 ]; then
    echo "error: no disks found (lsblk reported no TYPE=disk devices)." >&2
    exit 1
  fi

  echo "Select the disk to install itera-testhost onto:"
  echo
  i=1
  for label in "${labels[@]}"; do
    printf "  %2d) %s\n" "$i" "$label"
    i=$((i + 1))
  done
  echo
  printf "Enter a number [1-%d]: " "${#names[@]}"
  read -r choice

  case "$choice" in
    '' | *[!0-9]*)
      echo "error: '$choice' is not a number." >&2
      exit 1
      ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
    echo "error: choice out of range." >&2
    exit 1
  fi
  device="${names[$((choice - 1))]}"
fi

echo
echo "About to WIPE and install itera-testhost onto: $device"
lsblk -pno NAME,SIZE,TYPE,MOUNTPOINTS "$device" 2>/dev/null || true
echo
echo "This ERASES ALL DATA on $device. There is no undo."
printf "Type the device path exactly to confirm (%s): " "$device"
read -r confirm
if [ "$confirm" != "$device" ]; then
  echo "aborted: confirmation did not match." >&2
  exit 1
fi

echo
echo "Installing ${FLAKE}#${CONFIG} onto ${device} ..."
exec disko-install --flake "${FLAKE}#${CONFIG}" --disk "${DISK_NAME}" "$device" "$@"
