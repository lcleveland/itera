# carapace completion spec for the `itera` command (cli/itera.sh), as data.
#
# carapace is itera's external completer in nushell (see
# modules/nixos/core/shell/nushell.nix) and auto-loads specs from
# ~/.config/carapace/specs/. This file is the SINGLE source for both builds of
# the command, rendered to YAML at eval time by whoever installs it:
#
#   - `withTesthost = false` — the consumer spec, shipped to every itera system
#     by the `itera.programs.itera` home battery (modules/hjem/programs/itera.nix).
#   - `withTesthost = true`  — the full spec, with the itera-repo dev `testhost`
#     verbs, installed on the test hosts by dev/remote-access.nix.
#
# Previously these were two checked-in YAML files that were copies of each other
# minus the `testhost` block, hand-synced with cli/itera.sh — and they had already
# drifted (both described `update` as `nh os switch --update`, missing the
# `--refresh` path a remote flake takes). One tree, one place to edit.
#
# Keep in sync with cli/itera.sh: adding a subcommand means a `case` arm and a
# `usage` line there, plus an entry here.
{ lib, withTesthost }:
{
  name = "itera";
  description = "control your itera system";
  commands = [
    {
      name = "facter";
      description = "hardware reporting";
      commands = [
        {
          name = "report";
          description = "generate a nixos-facter report + itera.* tuning summary";
          completion.positional = [ [ "$files" ] ];
        }
      ];
    }
    {
      name = "rebuild";
      description = "rebuild this system from your flake (nh os switch)";
    }
    {
      name = "update";
      description = "fetch the newest config, then rebuild (nh os switch; --refresh for a remote flake, --update for a local one)";
    }
    {
      name = "boot";
      description = "rebuild, but apply on next reboot (nh os boot)";
    }
    {
      name = "update-boot";
      description = "fetch the newest config, apply on next reboot (nh os boot; --refresh for a remote flake, --update for a local one)";
    }
    {
      name = "gc";
      description = "prune old generations to free space (nh clean all)";
    }
    {
      name = "disks";
      description = "inspect internal fixed disks / prep one for autoClaim";
      commands = [
        {
          name = "list";
          description = "list internal fixed disks and how to add them as data drives";
        }
        {
          name = "prep";
          description = "wipe a disk blank so itera.disko.autoClaim will claim it";
          completion.positional = [ [ "$files" ] ];
        }
      ];
    }
    {
      name = "firmware";
      description = "update device firmware via fwupd";
      commands = [
        {
          name = "status";
          description = "show devices and their current firmware (fwupdmgr get-devices)";
        }
        {
          name = "refresh";
          description = "refresh firmware metadata from the LVFS (fwupdmgr refresh)";
        }
        {
          name = "update";
          description = "install available firmware updates (fwupdmgr update)";
        }
      ];
    }
  ]
  # The dev-only verbs. Absent from the consumer command (flake/cli.nix ships it
  # without their tools), so they must be absent from the consumer spec too.
  ++ lib.optional withTesthost {
    name = "testhost";
    description = "itera-repo test-host tooling (dev)";
    commands = [
      {
        name = "rebuild";
        description = "rebuild itera's test host in place from itera's flake";
      }
      {
        name = "install";
        description = "install itera-testhost onto a disk (disko-install)";
      }
    ];
  }
  ++ [
    {
      name = "help";
      description = "show usage";
    }
  ];
}
