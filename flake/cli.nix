# itera's command-line tooling, packaged.
#
# The `itera` command (cli/itera.sh) ships in two builds:
#
#   * `itera-consumer` — the system-management verbs (facter/rebuild/update/gc),
#     multi-arch. Shipped to every consumer by the `itera.cli` battery
#     (modules/nixos/core/cli.nix), so `itera` controls their own system.
#   * `itera` — the full build, which also carries the `testhost` verbs
#     (itera-repo dev tooling, hardcoded to itera's flake). Used via `nix run
#     .#itera` and baked onto the dev test hosts (dev/remote-access.nix). x86_64
#     only, because it routes to the x86-gated `install-itera-testhost`.
#
# Both read the SAME cli/itera.sh; the dispatcher shows/routes `testhost` only
# when its tools are on PATH, which is how the consumer build stays free of them
# (and of the disko-install closure).
#
# flake-parts deep-merges `perSystem.packages`, so these compose with
# `install-itera-testhost` (flake/test-host.nix) and `vm` (flake/vm.nix); the full
# dispatcher reaches the installer via `config.packages.install-itera-testhost`.
{ lib, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      iteraSrc = builtins.readFile ../cli/itera.sh;

      # Everything the system-management verbs shell out to. Shared by BOTH
      # builds so a new verb's tool is added once — the full dispatcher below is
      # this list plus the dev-only tools, not a second copy of it.
      #
      # `nh` (rebuild/update/gc), `nixos-facter` (the auto-regeneration the
      # rebuild verbs run before switching — see cli/itera.sh
      # `itera_facter_refresh`; pinned + offline, unlike facter-report.sh's
      # `nix run nixpkgs#nixos-facter`), and `fwupdmgr` (the `firmware` verbs)
      # are carried explicitly so each verb works even on a host with the
      # matching battery turned off.
      consumerInputs = [
        pkgs.nh
        pkgs.nixos-facter
        pkgs.fwupd
        config.packages.facter-report
        config.packages.itera-disks
        config.packages.itera-disks-prep
      ];
    in
    {
      packages = {
        # The facter report generator (repo-root facter-report.sh), packaged so
        # the dispatcher and `nix run .#facter-report` share one implementation.
        # It shells out to `nix run nixpkgs#nixos-facter` internally;
        # writeShellApplication appends runtimeInputs to PATH rather than
        # replacing it, so the ambient `nix` stays reachable. util-linux/pciutils
        # back the tuning summary.
        facter-report = pkgs.writeShellApplication {
          name = "facter-report";
          runtimeInputs = [
            pkgs.util-linux
            pkgs.pciutils
          ];
          text = builtins.readFile ../facter-report.sh;
        };

        # `itera disks`: lists internal fixed disks and prints a ready-to-paste
        # itera.disko.dataDrives block for each. Multi-arch and shipped to every
        # consumer (it is in itera-consumer's runtimeInputs below). Only lsblk is
        # special enough to carry explicitly; readlink/grep come from the host PATH
        # like facter-report.sh's awk.
        itera-disks = pkgs.writeShellApplication {
          name = "itera-disks";
          runtimeInputs = [ pkgs.util-linux ];
          text = builtins.readFile ../cli/itera-disks.sh;
        };

        # `itera disks prep`: destructively wipe a disk blank so itera.disko.autoClaim
        # will claim it. lsblk/wipefs/sgdisk are special; sudo/systemctl come from the
        # ambient PATH (writeShellApplication prepends runtimeInputs, keeping it).
        itera-disks-prep = pkgs.writeShellApplication {
          name = "itera-disks-prep";
          runtimeInputs = [
            pkgs.util-linux
            pkgs.gptfdisk
          ];
          text = builtins.readFile ../cli/itera-disks-prep.sh;
        };

        # In-place rebuild command. Moved here from dev/remote-access.nix so both
        # the on-host command and the dispatcher reuse the same package.
        itera-update = pkgs.writeShellApplication {
          name = "itera-update";
          # nh drives the rebuild; carry it explicitly so the command works even
          # if the nh battery is turned off on a host.
          runtimeInputs = [ pkgs.nh ];
          text = builtins.readFile ../dev/update-itera.sh;
        };

        # The consumer `itera`: system-management verbs only, so it stays
        # multi-arch and free of the disko-install closure.
        itera-consumer = pkgs.writeShellApplication {
          name = "itera";
          runtimeInputs = consumerInputs;
          text = iteraSrc;
        };
      }
      # The full dispatcher: adds the `testhost` verbs. x86_64-only because it
      # routes to the x86-gated `install-itera-testhost`; the test hosts (its bake
      # target) are x86_64 too.
      // lib.optionalAttrs (system == "x86_64-linux") {
        itera = pkgs.writeShellApplication {
          name = "itera";
          # The consumer tools plus the two the `testhost` verbs route to. Their
          # presence on PATH is exactly what makes the dispatcher show and accept
          # those verbs (see `require` in cli/itera.sh).
          runtimeInputs = consumerInputs ++ [
            config.packages.itera-update
            config.packages.install-itera-testhost
          ];
          text = iteraSrc;
        };
      };
    };
}
