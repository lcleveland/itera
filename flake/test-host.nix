# On-hardware test host output.
#
# itera defines no host of its own, so `dev/test-host.nix` assembles a bare-metal
# system purely for testing an install on real hardware, and this module exposes
# it as `nixosConfigurations.itera-testhost` — the sibling of the QEMU
# `itera-vm` in `flake/vm.nix`.
#
# Unlike `itera-vm`, there is no `disko.imageBuilder.pkgs = nixpkgs-stable`
# override: that workaround only matters for the `vmWithDisko` image builder on
# unstable. A real `disko-install` (and `nix flake check`) builds
# `system.build.toplevel` plus disko's format/mount scripts, which never touch
# that path. No `perSystem` packages either — this host is installed, not run
# locally.
#
# x86_64-only, matching `itera-vm` and the x86_64 gating the VM tests use.
{ inputs, ... }:
{
  flake.nixosConfigurations.itera-testhost = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.self.nixosModules.default
      ../dev/test-host.nix
    ];
  };
}
