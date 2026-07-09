# Interactive test VM for itera.
#
# itera is a module *layer*, not a host, so nothing here is a machine you can
# boot on its own. This module is the one place that turns the layer into a
# concrete, VM-bootable system. itera's stack is opt-out (on by default), so it
# comes along in full (core-boot, the disko disk layout, the tmpfs-root
# impermanence, and the DankMaterialShell + mango desktop); all this file does is
# supply the per-host bits the stack can't guess (a disko `device`, persisted
# user paths), opt out of hardening, and declare a login user, so we can boot it
# and poke at the real thing.
#
# It is wired up as `nixosConfigurations.itera-vm` in `flake/vm.nix`, and the
# convenient way to run it is the disko interactive VM:
#
#     nix run .#vm            # (= config.system.build.vmWithDisko)
#
# `vmWithDisko` (from the bundled disko module) creates blank qcow2 disks sized
# from the disko layout, runs disko's partitioning against them on boot, then
# boots the real system *through systemd-boot* — the only way to exercise
# `itera.disko` + `itera.impermanence` interactively, since they deliberately
# fight the plain NixOS-test / build-vm managed root.
#
# This file is dev-only tooling; it is NOT part of `nixosModules.default` and a
# downstream consumer never sees it.
{
  lib,
  ...
}:
{
  # ── The full itera stack (opt-out: on by default) ───────────────────────
  # `itera.enable`, the disko layout, and impermanence are all on by default;
  # we only fill in what they need for the VM and turn off what fights it.
  itera = {
    # disko is on by default but needs a target device. Its VM layer auto-remaps
    # the device onto the emulated disk, so /dev/vda is the right thing to point
    # at inside the VM.
    disko.device = "/dev/vda";

    # Wipe-every-boot tmpfs root (on by default), persisting only the curated set
    # (+ the dev user's home). If the shared-host-nix-store interaction misbehaves
    # at boot, set `impermanence.enable = false` to still exercise disko + the
    # desktop, then re-add.
    impermanence.users.dev.directories = [
      # Persist the dev user's home across the tmpfs-root wipe so logins/desktop
      # state survive a reboot (everything else outside /persist is ephemeral).
      ".config"
      ".local/share"
      ".cache"
    ];

    # nix-mineral hardening (on by default) interferes with the graphical stack
    # (see the README caveat; the desktop boot test disables it for the same
    # reason).
    hardening.enable = false;
  };

  networking.hostName = lib.mkForce "itera-vm";
  system.stateVersion = "25.05";

  # QEMU's virtio-gpu-gl makes wlroots draw a broken (upside-down) hardware
  # cursor; force software cursors (wlroots 0.19 still honors this variable).
  # It must reach both the DMS greeter's mango and the logged-in user's mango
  # session — both are launched by greetd, which rebuilds the session env from
  # PAM (so `systemd.services.greetd.environment` is discarded). greetd's PAM
  # stack runs pam_env against /etc/pam/environment, which NixOS generates from
  # `environment.sessionVariables`, so setting it here delivers it to both.
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

  # ── A login user (via itera's account battery) ──────────────────────────
  # `itera.users.<name>` creates the account AND enables hjem for it, so `dev`
  # inherits every itera home battery (mango autostart → `dms run`, the DMS
  # settings.json, the default keybinds) with the system-wide defaults. Log in
  # as dev / dev (initialPassword defaults to the username — fine for a dev VM;
  # this trips the expected "change before deploying" warning).
  itera.users.dev = {
    description = "itera test user";
    initialPassword = "dev";
  };

  # ── Disk / VM sizing ─────────────────────────────────────────────────────
  # Size of the blank qcow2 disko builds for the VM, and the guest RAM the
  # vmWithDisko runner allocates.
  disko.devices.disk.main.imageSize = "20G";
  disko.memSize = 4096;

  # ── virtio guest drivers ──────────────────────────────────────────────────
  # The VM boots through systemd-boot off an emulated virtio disk and renders on
  # the virtio-gpu configured below, so the guest kernel needs the virtio
  # drivers. itera.hardware's curated availableKernelModules default already
  # carries virtio_pci/blk/scsi (to find and mount /dev/vda in the initrd) and
  # virtio_net (the NIC), so the only extra the VM needs is virtio_gpu, forced
  # early so the console/framebuffer comes up for the display + autoresize. This
  # is the whole hardware side of the VM — there is no hardware-configuration.nix.
  itera.hardware.initrd.kernelModules = [ "virtio_gpu" ];

  # ── Graphical QEMU tuning (only applied to the vmWithDisko runner) ────────
  virtualisation.vmVariantWithDisko = {
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      # wlroots/mango wants a GPU; give it virtio-gpu with GL in a GTK window.
      qemu.options = [
        "-vga none"
        # virtio-gpu has no vgamem; its video-RAM analog is the `hostmem` host
        # memory window, which only applies with `blob=on` (host-backed blob
        # resources). A larger window gives ultrawide framebuffers/textures
        # headroom.
        "-device virtio-gpu-gl,hostmem=4G,blob=on"
        # zoom-to-fit=off => resizing the GTK window changes the guest
        # resolution (autoresize; wlroots/mango honor the virtio-gpu mode
        # change) instead of scaling the image. No xres/yres pinning, which
        # would otherwise disable autoresize.
        "-display gtk,gl=on,zoom-to-fit=off"
      ];
      # Persistence must be mounted before stage-2 activation bind-mounts the
      # persisted paths back into the fresh tmpfs root (disko doc's example).
      fileSystems."/persist".neededForBoot = true;
    };
  };

  # ── Fallback if the DMS greetd greeter won't render under virtio-gpu ──────
  # The greeter needs a real seat and may not come up in the VM. If login never
  # appears, drop the greeter and autologin `dev` on tty1 straight into a mango
  # session (mango's autostart then launches dms):
  #
  #   itera.desktop.dankMaterialShell.greeter.enable = false;
  #   services.getty.autologinUser = "dev";
  #   programs.bash.loginShellInit = ''
  #     if [ "$(tty)" = "/dev/tty1" ]; then exec mango; fi
  #   '';
}
