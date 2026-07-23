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
{ inputs, lib, ... }:
{
  flake.nixosConfigurations.itera-testhost = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    # Give dev modules (remote-access.nix) access to flake outputs — it installs
    # the `itera` command from `inputs.self.packages`.
    specialArgs = { inherit inputs; };
    modules = [
      inputs.self.nixosModules.default
      ../dev/test-host.nix
      # The standardized `itera` login user (dev-only, shared with the VM).
      ../dev/test-user.nix
      # SSH in + `itera-update` for in-place rebuilds (dev-only, shared with the VM).
      ../dev/remote-access.nix
    ];
  };

  # Interactive installer for the above, meant to be run from a live ISO:
  #
  #     nix run 'github:lcleveland/itera#install-itera-testhost'
  #
  # It lists the machine's disks, confirms the wipe, and hands the chosen device
  # to disko's one-shot installer as `--disk main <device>`. This is just itera's
  # general-purpose installer (`itera.lib.mkInstaller`, the same one downstream
  # flakes build) baked to itera's own flake and preselected to the `itera-testhost`
  # host, with disko-install pinned to itera's own disko input so it matches
  # `itera.disko`'s layout. x86_64-only to match the host it installs.
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.install-itera-testhost = inputs.self.lib.mkInstaller pkgs {
        name = "install-itera-testhost";
        flake = "github:lcleveland/itera";
        host = "itera-testhost";
        diskoInstall = inputs.disko.packages.${system}.disko-install;
      };
    };
}
