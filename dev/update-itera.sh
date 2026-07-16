#!/usr/bin/env bash
# In-place remote update for an installed itera test system.
#
# itera's test hosts (itera-vm, itera-testhost) install straight from the flake
# on GitHub. Once installed, you don't want to reinstall from the live ISO every
# time the config changes — you want to pull the newest commit and rebuild in
# place. That is all this does: `nh os switch` against the remote flake.
#
# It backs the `itera testhost rebuild` subcommand (see cli/itera.sh) and is
# packaged as `itera-update` (flake/cli.nix); the full `itera` dispatcher is what
# the test systems bake onto PATH (see dev/remote-access.nix). SSH in and run:
#
#     itera testhost rebuild
#
# `nh os switch` is itera's rebuild front-end (see modules/nixos/core/nh.nix): it
# builds the new system with a live build-tree view, shows a diff of what
# changed against the current generation, prompts for confirmation, then
# switches. It self-elevates with sudo, so this script is NOT run under sudo.
#
# The flake attr defaults to the running host's own name — hostnames match the
# flake attr names, so `-H "$(uname -n)"` resolves to `#itera-vm` on the VM and
# `#itera-testhost` on bare metal. Point it at a fork/branch to test unmerged
# work (mirrors the installer's ITERA_INSTALL_FLAKE):
#
#     ITERA_UPDATE_FLAKE=github:you/itera itera-update
#
# Note the value is now a bare flake ref with NO `#attr` suffix — nh takes the
# configuration name via `-H`, not as part of the flake ref.
#
# Any extra arguments are passed straight through to `nh os switch` (e.g.
# `itera-update --dry` to preview, `-v` for more logging). To stage the change
# for next boot instead of switching now, run `nh os boot` directly with the
# same flake/`-H` arguments.
#
# `--refresh` (a native `nh` flag) refreshes the flake to its latest revision so
# it always fetches the newest commit. `switch` applies most changes live; a
# kernel/initrd change still needs a reboot.
set -euo pipefail

FLAKE="${ITERA_UPDATE_FLAKE:-github:lcleveland/itera}"

echo "Updating from ${FLAKE}#$(uname -n) …"
exec nh os switch "$FLAKE" --hostname "$(uname -n)" --refresh "$@"
