#!/usr/bin/env bash
# Remote bootstrap for installing itera's `itera-testhost` from a NixOS live ISO.
#
# The live ISO ships with the nix-command/flakes experimental features disabled
# and partitioning needs root, so rather than typing the full `nix run`
# invocation, pipe this straight into bash as root:
#
#   curl -fsSL https://raw.githubusercontent.com/lcleveland/itera/main/install-testhost.sh | sudo bash
#
# Pass a device to skip the disk menu (and any extra disko-install flags after):
#
#   curl -fsSL https://raw.githubusercontent.com/lcleveland/itera/main/install-testhost.sh | sudo bash -s -- /dev/nvme0n1
#
# Install from a fork/branch instead by setting ITERA_INSTALL_FLAKE in root's env:
#
#   curl -fsSL .../install-testhost.sh | sudo env ITERA_INSTALL_FLAKE=github:you/itera bash
#
# All it does is enable the experimental features and `nix run` the real
# installer (itera's general-purpose installer from `itera.lib.mkInstaller`, baked
# to the itera-testhost host and packaged as `#install-itera-testhost`), which then
# lists disks, confirms, and hands off to disko-install. Reads for the menu come
# from /dev/tty, so the pipe doesn't eat them.
set -euo pipefail

FLAKE="${ITERA_INSTALL_FLAKE:-github:lcleveland/itera}"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — it partitions and installs to a disk. Pipe it into 'sudo bash':" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/lcleveland/itera/main/install-testhost.sh | sudo bash" >&2
  exit 1
fi

exec nix --extra-experimental-features 'nix-command flakes' \
  run "${FLAKE}#install-itera-testhost" -- "$@"
