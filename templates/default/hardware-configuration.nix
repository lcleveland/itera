# PLACEHOLDER — REPLACE THIS FILE.
#
# This is a machine-independent stub so the template evaluates out of the box.
# It will NOT boot real hardware as-is. On the target machine, generate the real
# thing and overwrite this file:
#
#     nixos-generate-config --show-hardware-config --no-filesystems > hardware-configuration.nix
#
# (drop `--no-filesystems` if you are NOT using `itera.disko`, so the generator
# also captures your actual `fileSystems` entries).
#
# itera provides the bootloader, kernel/initrd, locale and networking. The parts
# that MUST come from here — because they depend on the specific hardware — are
# the initrd kernel modules, CPU microcode, and (when not using `itera.disko`)
# the filesystem/swap layout.
{ lib, modulesPath, ... }:
{
  imports = [
    # Sane defaults for a QEMU/VM guest so `nixos-rebuild build` works before you
    # generate the real config. Remove this on real hardware.
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Modules the initrd needs to find and mount the root device. `nixos-generate-config`
  # fills these in for your actual disk controller.
  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "xhci_pci"
      "virtio_pci"
      "sr_mod"
      "virtio_blk"
    ];
    initrd.kernelModules = [ ];
    kernelModules = [ ];
    extraModulePackages = [ ];
  };

  # Root filesystem. When you enable `itera.disko`, DELETE this block — disko
  # declares the filesystems for you. Otherwise replace it with your real layout
  # (this placeholder just points at a conventional label).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  # Enable DHCP per-interface by default; NetworkManager (via itera.networking)
  # takes over on a running system.
  networking.useDHCP = lib.mkDefault true;
}
