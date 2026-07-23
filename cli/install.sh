# itera's host-agnostic installer, meant to be run from a booted NixOS live ISO.
#
# It picks a host from the flake's `nixosConfigurations`, picks a whole disk,
# confirms the (destructive) wipe, and hands off to disko-install (partition +
# format + mount + nixos-install in one). When the chosen host opts into
# `itera.disko.encryption`, it also handles the LUKS passphrase and — for
# `encryption.tpm2.enable` hosts — enrolls the TPM2 keyslot right after install,
# so a passwordless-auto-unlock machine comes up on the FIRST boot with no
# separate post-install step.
#
# This one script backs BOTH itera's own dev installer (`install-itera-testhost`,
# which bakes in itera's flake + the `itera-testhost` host) AND the reusable
# installer downstream flakes build with `itera.lib.mkInstaller` (see
# `lib/installer.nix`). The builder bakes the flake / disk defaults into the
# environment below; nothing here is itera-repo-specific.
#
# Runtime knobs (all optional — the mkInstaller builder supplies the defaults):
#   ITERA_INSTALL_FLAKE  flake ref to install from      (e.g. github:you/config)
#   ITERA_DISK_NAME      the disk key in itera.disko     (default: main)
#   ITERA_HOST           preselect a host, skipping the  (default: unset → menu)
#                        host menu/first-arg
#
# writeShellApplication supplies `set -euo pipefail`, a shebang, and a shellcheck
# pass, so this file is plain bash with no preamble of its own.

# The live ISO ships with flakes disabled, and disko-install shells out to more
# `nix` commands — export the features so every child nix process inherits them
# (extra-* appends, so any existing NIX_CONFIG is preserved). accept-flake-config
# takes the flake's substituters/caches without an interactive prompt.
export NIX_CONFIG="extra-experimental-features = nix-command flakes
accept-flake-config = true
${NIX_CONFIG:-}"

FLAKE="${ITERA_INSTALL_FLAKE:-}"
DISK_NAME="${ITERA_DISK_NAME:-main}"

if [ -z "$FLAKE" ]; then
  echo "error: ITERA_INSTALL_FLAKE is not set — no flake to install from." >&2
  echo "       (the mkInstaller builder normally bakes this in; set it by hand" >&2
  echo "        to override, e.g. ITERA_INSTALL_FLAKE=. for a local clone.)" >&2
  exit 1
fi

# Read interactive answers from the controlling terminal, not stdin: when this is
# reached through a `curl … | sudo bash` bootstrap, stdin is the piped script, so
# a plain `read` would hit EOF instead of the keyboard.
if [ -r /dev/tty ]; then
  TTY=/dev/tty
else
  TTY=/dev/stdin
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root — this partitions and installs to a disk." >&2
  exit 1
fi

# ---- host ------------------------------------------------------------------
# A baked ITERA_HOST wins outright (the dev testhost installer uses it). Otherwise
# the first non-flag argument is the host; both are validated against the flake's
# actual nixosConfigurations so a typo fails fast instead of deep inside disko.
mapfile -t HOSTS < <(
  nix eval --json "${FLAKE}#nixosConfigurations" --apply builtins.attrNames 2>/dev/null \
    | tr -d '[]"' | tr ',' '\n' | sed '/^$/d'
)
if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "error: no nixosConfigurations found in ${FLAKE}." >&2
  exit 1
fi

host_is_known() {
  local h
  for h in "${HOSTS[@]}"; do
    [ "$h" = "$1" ] && return 0
  done
  return 1
}

host="${ITERA_HOST:-}"
if [ -z "$host" ] && [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  host="$1"
  shift
fi

if [ -n "$host" ] && ! host_is_known "$host"; then
  echo "error: unknown host '$host' (known: ${HOSTS[*]})." >&2
  exit 1
fi

if [ -z "$host" ]; then
  echo "Select the host to install:"
  echo
  i=1
  for h in "${HOSTS[@]}"; do
    printf "  %2d) %s\n" "$i" "$h"
    i=$((i + 1))
  done
  echo
  printf "Enter a number [1-%d]: " "${#HOSTS[@]}"
  read -r choice <"$TTY"
  case "$choice" in
    '' | *[!0-9]*)
      echo "error: '$choice' is not a number." >&2
      exit 1
      ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#HOSTS[@]}" ]; then
    echo "error: choice out of range." >&2
    exit 1
  fi
  host="${HOSTS[$((choice - 1))]}"
fi

# ---- disk ------------------------------------------------------------------
# Next non-flag argument is the device; anything after it goes to disko-install.
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

  echo
  echo "Select the disk to install '$host' onto:"
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

# ---- confirm ---------------------------------------------------------------
echo
echo "About to WIPE and install '$host' onto: $device"
lsblk -pno NAME,SIZE,TYPE,MOUNTPOINTS "$device" 2>/dev/null || true
echo
echo "This ERASES ALL DATA on $device. There is no undo."
printf "Type the device path exactly to confirm (%s): " "$device"
read -r confirm <"$TTY"
if [ "$confirm" != "$device" ]; then
  echo "aborted: confirmation did not match." >&2
  exit 1
fi

# ---- read the host's disko knobs -------------------------------------------
# Everything below is driven by the EVALUATED config, so this installer stays in
# lockstep with the host definition and carries no duplicated encryption policy.
cfg_attr() {
  # `nix eval --raw` errors on a null (nullOr str passwordFile); `|| true` maps
  # that to an empty string, which callers treat as "unset".
  nix eval --raw "${FLAKE}#nixosConfigurations.${host}.config.itera.disko.$1" 2>/dev/null || true
}
cfg_bool() {
  nix eval "${FLAKE}#nixosConfigurations.${host}.config.itera.disko.$1" 2>/dev/null || echo false
}

enc_enabled="$(cfg_bool encryption.enable)"
tpm2_enabled="$(cfg_bool encryption.tpm2.enable)"
pwfile="$(cfg_attr encryption.passwordFile)"

# ---- encryption passphrase -------------------------------------------------
# When the host encrypts the disk and its config points at a passwordFile that
# doesn't exist yet, prompt for a NEW passphrase and write it there. disko reads
# that file to format the LUKS containers (no interactive prompt), and — for TPM2
# hosts — we reuse the very same file to enroll the TPM keyslot below, so the
# whole install (including passwordless auto-unlock) completes in one pass with no
# post-install step. The file lives only on the live ISO's tmpfs and is shredded
# when we exit. A passwordFile that already exists (e.g. a fully automated,
# non-interactive install) is used as-is and left alone. A host that leaves
# passwordFile null instead gets disko's own interactive passphrase prompt at
# format time (and, if it also wants TPM2, the post-first-boot enroll path below).
if [ "$enc_enabled" = "true" ] && [ -n "$pwfile" ] && [ ! -r "$pwfile" ]; then
  echo
  echo "This host encrypts the disk. Choose a passphrase (it also becomes the TPM2"
  echo "recovery passphrase). It is NEVER written to the installed system."
  while :; do
    printf "Enter a new disk-encryption passphrase: "
    read -rs pw1 <"$TTY"; echo
    printf "Confirm passphrase: "
    read -rs pw2 <"$TTY"; echo
    if [ -z "$pw1" ]; then
      echo "error: passphrase must not be empty." >&2
    elif [ "$pw1" != "$pw2" ]; then
      echo "error: passphrases did not match." >&2
    else
      break
    fi
  done
  ( umask 077; mkdir -p "$(dirname "$pwfile")"; printf '%s' "$pw1" >"$pwfile" )
  unset pw1 pw2
  # Shred the passphrase file whenever the installer exits (success, error, or
  # Ctrl-C) so it never lingers on the ISO's tmpfs.
  # shellcheck disable=SC2064
  trap "shred -u '$pwfile' 2>/dev/null || rm -f '$pwfile'" EXIT
fi

# ---- install ---------------------------------------------------------------
# Use a pinned disko-install when one is on PATH (itera's dev installer bakes its
# own disko input in, so the layout matches itera.disko exactly); otherwise fetch
# it with `nix run` (the default for a downstream mkInstaller, which stays free of
# the disko closure). `--disk <name> <device>` overrides the placeholder device.
if command -v disko-install >/dev/null 2>&1; then
  disko_install=(disko-install)
else
  disko_install=(nix run 'github:nix-community/disko/latest#disko-install' --)
fi

echo
echo "Installing ${FLAKE}#${host} onto ${device} ..."
# Redirect stdin from $TTY: when no passwordFile was configured (plain interactive
# encryption), disko shells out to cryptsetup, which prompts for the passphrase on
# its stdin. Under `curl … | sudo bash` our stdin is the piped script (already at
# EOF), so without this the prompt gets empty input and never pauses. $TTY is the
# keyboard; harmless when we supplied a passwordFile above (disko reads the file
# and prompts for nothing). NOT `exec`: control must return so the TPM2 step runs.
"${disko_install[@]}" --flake "${FLAKE}#${host}" --disk "${DISK_NAME}" "$device" "$@" <"$TTY"

# ---- TPM2 auto-unlock enrollment -------------------------------------------
# Only when the chosen host opts in (itera.disko.encryption.tpm2.enable). The LUKS
# containers were just formatted with the passphrase above; enrolling the TPM2
# keyslot now — on the target hardware, against the live PCRs (PCR 7 = Secure Boot
# state, unchanged between ISO and installed system) — means the FIRST boot unlocks
# with no prompt and no separate first-boot step.
if [ "$tpm2_enabled" = "true" ]; then
  pcrs="$(cfg_attr encryption.tpm2.pcrs)"

  # Enroll every present container: root always, swap only when a swap partition
  # is declared. disko labels the raw partitions disk-<disk>-<part>; cryptenroll
  # writes the TPM2 token into the LUKS header on those, not the mapper devices.
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
    echo "      was found, so enrollment can't run here. After the first boot, run" >&2
    echo "      once:  sudo itera-tpm2-enroll" >&2
  fi
fi
