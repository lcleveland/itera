# itera's command-line tooling, packaged.
#
# Exposes the `itera` dispatcher (see dev/itera.sh) plus the two commands it
# gained a package for. flake-parts deep-merges `perSystem.packages` across all
# imported modules, so these compose with `install-itera-testhost` (defined in
# flake/test-host.nix) and `vm` (flake/vm.nix) — the dispatcher reaches the
# installer via `config.packages.install-itera-testhost`.
#
# The `itera` package is what dev/remote-access.nix bakes onto the test hosts, so
# `itera <cmd>` works over SSH; it is also `nix run`-able from anywhere.
{ lib, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
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
      }
      # The dispatcher. x86_64-only because it routes to the x86-gated
      # `install-itera-testhost`; the test hosts (its bake target) are x86_64 too.
      // lib.optionalAttrs (system == "x86_64-linux") {
        itera = pkgs.writeShellApplication {
          name = "itera";
          runtimeInputs = [
            config.packages.itera-update
            config.packages.facter-report
            config.packages.install-itera-testhost
          ];
          text = builtins.readFile ../dev/itera.sh;
        };
      };
    };
}
