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
        # multi-arch and free of the disko-install closure. `nh` backs
        # rebuild/update/gc (carried explicitly like itera-update does).
        itera-consumer = pkgs.writeShellApplication {
          name = "itera";
          runtimeInputs = [
            pkgs.nh
            config.packages.facter-report
          ];
          text = iteraSrc;
        };
      }
      # The full dispatcher: adds the `testhost` verbs. x86_64-only because it
      # routes to the x86-gated `install-itera-testhost`; the test hosts (its bake
      # target) are x86_64 too.
      // lib.optionalAttrs (system == "x86_64-linux") {
        itera = pkgs.writeShellApplication {
          name = "itera";
          runtimeInputs = [
            pkgs.nh
            config.packages.facter-report
            config.packages.itera-update
            config.packages.install-itera-testhost
          ];
          text = iteraSrc;
        };
      };
    };
}
