# Interactive installer for itera's `itera-testhost`, meant to be run from a
# booted NixOS live ISO. It lists the machine's whole disks, lets you pick one,
# confirms the (destructive) wipe, then hands off to disko-install — saving you
# from spelling out the flake ref, config name, and `--disk main <device>` by
# hand.
#
# Wired up as the flake package `install-itera-testhost` in `flake/test-host.nix`.
# The live ISO ships with flakes disabled and you need root to partition, so the
# invocation has to enable the experimental features AND run as root:
#
#   sudo nix --extra-experimental-features 'nix-command flakes' \
#     run 'github:lcleveland/itera#install-itera-testhost'                    # pick from a menu
#   sudo nix --extra-experimental-features 'nix-command flakes' \
#     run 'github:lcleveland/itera#install-itera-testhost' -- /dev/nvme0n1    # skip the menu
#
# Any extra arguments after the device are forwarded to disko-install. Override
# the flake it installs from (e.g. a local clone) with the ITERA_INSTALL_FLAKE
# environment variable, keeping it in root's env with `sudo env`:
#
#   sudo env ITERA_INSTALL_FLAKE=. nix --extra-experimental-features \
#     'nix-command flakes' run '.#install-itera-testhost'
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own.

# The `--extra-experimental-features` flag only enables flakes for the outer
# `nix run`; disko-install shells out to more `nix` commands that would fail the
# same way. Export it so every child nix process inherits it (extra-* appends, so
# any existing NIX_CONFIG is preserved).
export NIX_CONFIG="extra-experimental-features = nix-command flakes
${NIX_CONFIG:-}"

FLAKE="${ITERA_INSTALL_FLAKE:-github:lcleveland/itera}"
CONFIG="itera-testhost"
DISK_NAME="main"

# Read interactive answers from the controlling terminal, not stdin: when this is
# reached through the install-testhost.sh bootstrap (`curl … | sudo bash`), stdin
# is the piped script, so a plain `read` would hit EOF instead of the keyboard.
if [ -r /dev/tty ]; then
  TTY=/dev/tty
else
  TTY=/dev/stdin
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root — this partitions and installs to a disk." >&2
  echo "       re-run under sudo, e.g.:" >&2
  echo "         sudo nix --extra-experimental-features 'nix-command flakes' \\" >&2
  echo "           run '<flake>#install-itera-testhost'" >&2
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
  read -r choice <"$TTY"

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
read -r confirm <"$TTY"
if [ "$confirm" != "$device" ]; then
  echo "aborted: confirmation did not match." >&2
  exit 1
fi

echo
echo "Installing ${FLAKE}#${CONFIG} onto ${device} ..."
disko-install --flake "${FLAKE}#${CONFIG}" --disk "${DISK_NAME}" "$device" "$@"

# TPM2 auto-unlock enrollment — only when the target config opts in
# (itera.disko.encryption.tpm2.enable). disko-install has just formatted the LUKS
# containers with the install passphrase; enrolling the TPM2 keyslot now — on the
# target hardware, against the live PCRs (PCR 7 = Secure Boot state, unchanged
# between ISO and installed system) — means the FIRST boot already unlocks with no
# prompt and no separate first-boot step. The knobs are read straight from the
# evaluated config so this stays in lockstep with `itera.disko.encryption`.
cfg_attr() {
  # `nix eval --raw` errors on a null (nullOr str passwordFile); `|| true` maps that
  # to an empty string, which the callers treat as "unset".
  nix eval --raw "${FLAKE}#nixosConfigurations.${CONFIG}.config.itera.disko.$1" 2>/dev/null || true
}

if [ "$(nix eval "${FLAKE}#nixosConfigurations.${CONFIG}.config.itera.disko.encryption.tpm2.enable" 2>/dev/null || echo false)" = "true" ]; then
  pcrs="$(cfg_attr encryption.tpm2.pcrs)"
  pwfile="$(cfg_attr encryption.passwordFile)"

  # Enroll every present container: root always, swap only when a swap partition is
  # declared. disko labels the raw partitions disk-<disk>-<part>; cryptenroll writes
  # the TPM2 token into the LUKS header on those, not the /dev/mapper devices.
  targets=("/dev/disk/by-partlabel/disk-${DISK_NAME}-root")
  [ -n "$(cfg_attr swapSize)" ] && targets+=("/dev/disk/by-partlabel/disk-${DISK_NAME}-swap")
  command -v udevadm >/dev/null && udevadm settle || true

  if [ -n "$pwfile" ] && [ -r "$pwfile" ]; then
    echo
    echo "Enrolling TPM2 (PCRs ${pcrs}) so this host unlocks without a passphrase ..."
    for t in "${targets[@]}"; do
      if [ -e "$t" ]; then
        systemd-cryptenroll --unlock-key-file="$pwfile" --wipe-slot=tpm2 \
          --tpm2-device=auto --tpm2-pcrs="$pcrs" "$t"
      else
        echo "warning: $t not found; skipping TPM2 enrollment for it." >&2
      fi
    done
  else
    echo
    echo "NOTE: TPM2 auto-unlock is enabled but no readable encryption.passwordFile" >&2
    echo "      was found, so enrollment can't run non-interactively here. After the" >&2
    echo "      first boot, run once:  sudo itera-tpm2-enroll" >&2
  fi
fi
