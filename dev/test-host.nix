# On-hardware test host for itera.
#
# itera is a module *layer*, not a host, so nothing here is a machine you can
# boot on its own. This is the bare-metal sibling of `dev/vm.nix`: where that
# file assembles a QEMU-bootable system for `nix run .#vm`, this one assembles a
# system you can install straight onto real hardware from a NixOS live ISO —
# giving us one committed config that exercises the *full* opt-out itera stack
# (disko + tmpfs-root impermanence + hardening + the DankMaterialShell + mango
# desktop + WezTerm) on actual silicon. Because the stack is opt-out (on by
# default), all this file supplies is the handful of per-host values the layer
# can't guess; the login user is the shared `itera` account from
# `dev/test-user.nix`.
#
# It is wired up as `nixosConfigurations.itera-testhost` in `flake/test-host.nix`.
# Install it from a booted live ISO (as root), pointing `--disk main` at the REAL
# target disk (see the `itera.disko.device` note below):
#
#     nix run 'github:nix-community/disko#disko-install' -- \
#       --flake '.#itera-testhost' --disk main /dev/<your-real-disk>
#
# This file is dev-only tooling; it is NOT part of `nixosModules.default` and a
# downstream consumer never sees it.
_: {
  # ── The full itera stack (opt-out: on by default) ───────────────────────
  # disko, impermanence, hardening, and the desktop are all on by default; we
  # only fill in what they need for a real machine. Unlike `dev/vm.nix`, there
  # are NO QEMU workarounds here (no virtio_gpu initrd module, no software-GL
  # WezTerm wrapper, no WLR_NO_HARDWARE_CURSORS, no vmVariantWithDisko sizing):
  # on real hardware the broad `itera.hardware.initrd.availableKernelModules`
  # default boots the machine and the real GPU drives the desktop.
  itera = {
    # disko is on by default but needs a target device, and partitioning is
    # destructive with no safe default. This is a PLACEHOLDER only: it exists so
    # the config evaluates (satisfying itera.disko's non-empty-device assertion)
    # and `nix flake check` stays green. It is a deliberately non-existent path
    # so a forgotten `--disk` fails safe (disko errors on a missing device
    # instead of wiping a real one). At install, `disko-install --disk main
    # /dev/<real>` overrides `disko.devices.disk.main.device`, so THIS value is
    # never actually written to.
    disko.device = "/dev/disk/by-id/CHANGE-ME-disko-install-overrides-this";

    # A swap partition sized above this box's RAM (~16 GiB) so the test host
    # exercises hibernation end-to-end: with swap present, itera.disko.resume
    # (on by default) wires boot.resumeDevice to this partition and the systemd
    # initrd emits the matching `resume=` kernel param, so `systemctl hibernate`
    # works. disko only lays this partition down at install time, so a machine
    # installed before this was added needs a fresh disko-install to gain it.
    disko.swapSize = "20G";

    # CPU vendor stays "auto" (both microcodes, no kvm-* module) for a
    # hardware-agnostic image. Set to "intel"/"amd" to also load the matching
    # kvm-* module for virtualization on this box:
    #   hardware.cpu = "amd";

    networking.hostName = "itera-testhost";

    # Pin the release this host was installed from; set once, never change.
    nix.stateVersion = "25.05";
  };

  # The login user (the standardized `itera` account) and its persisted home live
  # in the shared dev/test-user.nix, imported alongside this file in
  # flake/test-host.nix.
}
