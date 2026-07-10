#!/usr/bin/env bash
# In-place remote update for an installed itera test system.
#
# itera's test hosts (itera-vm, itera-testhost) install straight from the flake
# on GitHub. Once installed, you don't want to reinstall from the live ISO every
# time the config changes — you want to pull the newest commit and rebuild in
# place. That is all this does: `nixos-rebuild switch` against the remote flake.
#
# It is baked into both test systems as the `itera-update` command (see
# dev/remote-access.nix). SSH in and run it:
#
#     itera-update
#
# The flake attr defaults to the running host's own name — hostnames match the
# flake attr names, so this resolves to `#itera-vm` on the VM and
# `#itera-testhost` on bare metal. Point it at a fork/branch to test unmerged
# work (mirrors the installer's ITERA_INSTALL_FLAKE):
#
#     ITERA_UPDATE_FLAKE=github:you/itera#itera-testhost itera-update
#
# Any extra arguments are passed straight through to nixos-rebuild, e.g.
# `itera-update boot` to stage the change for next boot instead of switching now.
#
# `--refresh` bypasses the flake eval cache so it always fetches the newest
# commit. `switch` applies most changes live; a kernel/initrd change still needs
# a reboot.
set -euo pipefail

FLAKE="${ITERA_UPDATE_FLAKE:-github:lcleveland/itera#$(uname -n)}"

echo "Updating from ${FLAKE} …"
exec sudo nixos-rebuild switch --flake "$FLAKE" --refresh "$@"
