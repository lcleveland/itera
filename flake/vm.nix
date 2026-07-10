# Interactive test VM output.
#
# itera defines no host of its own, so `dev/vm.nix` assembles one purely for
# local testing and this module exposes it. Two outputs:
#
#   * `nixosConfigurations.itera-vm` — the assembled demo system.
#   * `packages.<x86_64-linux>.vm`   — disko's interactive VM runner
#                                       (`config.system.build.vmWithDisko`),
#                                       a runnable script, so `nix run .#vm`
#                                       creates the disks, partitions them with
#                                       disko, and boots the real system.
#
# x86_64-only, matching KVM availability and the x86_64 gating the VM tests in
# `flake/checks.nix` already use.
{ inputs, lib, ... }:
{
  flake.nixosConfigurations.itera-vm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.self.nixosModules.default
      ../dev/vm.nix
      # The standardized `itera` login user (dev-only, shared with the testhost).
      ../dev/test-user.nix
      # SSH in + `itera-update` for in-place rebuilds (dev-only, shared with the
      # testhost). The QEMU host→guest port forward lives in dev/vm.nix.
      ../dev/remote-access.nix

      # disko builds its base disk image inside a `pkgs.vmTools` builder VM.
      # Current nixpkgs-unstable's vmTools rejects the aggregate-kernel argument
      # disko (HEAD) still passes it, so building `diskoImages` fails on unstable.
      # The image is just an empty partitioned/formatted disk (copyNixStore =
      # false), so it is safe to build with the older stable vmTools — which
      # still accepts disko's interface. This only affects the image builder,
      # never the running system (built from unstable).
      { disko.imageBuilder.pkgs = inputs.nixpkgs-stable.legacyPackages."x86_64-linux"; }
    ];
  };

  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      # disko's `vmWithDisko` runner already builds its qcow2 disk in a temp dir it
      # cleans on exit, but the inner nixos VM runner writes the OVMF EFI variables
      # store (`itera-vm-efi-vars.fd`) into the *launch* directory and leaves it
      # behind. It honors $NIX_EFI_VARS, so redirect that into a temp dir we remove
      # on exit — nothing lands in the working tree. (An unset EFI store just gets
      # re-seeded from OVMF_VARS.fd each boot, which suits this wipe-every-boot VM.)
      packages.vm =
        let
          runner = inputs.self.nixosConfigurations.itera-vm.config.system.build.vmWithDisko;
        in
        pkgs.writeShellApplication {
          name = "disko-vm";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            export NIX_EFI_VARS="''${NIX_EFI_VARS:-$tmp/itera-vm-efi-vars.fd}"
            exec ${runner}/bin/disko-vm "$@"
          '';
        };
    };
}
