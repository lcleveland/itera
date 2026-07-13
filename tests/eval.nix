# Evaluation check for itera's system batteries (disko, impermanence, and the
# core-boot defaults: bootloader, nix, locale, networking).
#
# Full VM boot-tests of partitioning and a tmpfs root fight the NixOS test
# framework's own disk/root setup, so instead we evaluate a NixOS configuration
# with the features enabled and assert the generated config is what we expect.
# `nix build` on this derivation forces the evaluation and fails loudly if any
# assertion is false. The core-boot batteries additionally get a real EFI boot
# test in tests/nixos/core-boot.nix.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;

  # disko + impermanence on (overriding mkConfig's defaults) so this eval
  # exercises partitioning and the tmpfs root alongside the core-boot batteries.
  diskoOn = {
    itera.disko = {
      enable = true;
      device = "/dev/vda";
    };
    itera.impermanence.enable = true;
  };
  mkEval =
    extra:
    mkConfig [
      diskoOn
      extra
    ];

  # A normal user account, so this eval exercises the default curated per-user
  # home persistence (itera.impermanence.homes).
  cfg = mkEval { itera.users.testuser = { }; };

  # Two extra evals to exercise the hibernation resume wiring (itera.disko.resume):
  # a swap partition sized for hibernation, and the same with resume opted out.
  swapOn = mkEval { itera.disko.swapSize = "16G"; };
  swapNoResume = mkEval {
    itera.disko.swapSize = "16G";
    itera.disko.resume = false;
  };

  # NVIDIA is opt-in (default off). Evaluate a plain-defaults config to assert it
  # stays inert, and an enabled + PRIME-offload config to assert the wiring.
  nvidiaOn = mkEval {
    itera.nvidia = {
      enable = true;
      prime = {
        enable = true;
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
  };

  subvolumes = cfg.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  persistence = cfg.environment.persistence."/persist";

  # impermanence coerces string entries into attrsets ({ file = ...; } /
  # { directory = ...; }); tolerate either shape.
  fileNames = map (f: f.file or f) persistence.files;
  dirNames = map (d: d.directory or d) persistence.directories;
  userDirs = name: map (d: d.directory or d) persistence.users.${name}.directories;

  checks = {
    # disko + impermanence
    "disko provides a /nix subvolume" = subvolumes ? "/nix";
    "disko provides a /persist subvolume" = subvolumes ? "/persist";
    "root filesystem is tmpfs" = cfg.fileSystems."/".fsType == "tmpfs";
    "machine-id is persisted by default" = builtins.elem "/etc/machine-id" fileNames;
    "NetworkManager connections are persisted" =
      builtins.elem "/etc/NetworkManager/system-connections" dirNames;
    "NetworkManager runtime state is persisted" = builtins.elem "/var/lib/NetworkManager" dirNames;
    "timesyncd clock state is persisted" = builtins.elem "/var/lib/systemd/timesync" dirNames;
    # The DMS greeter is on by default (itera.enable), so its cache dir — holding
    # the remembered last-user/session — is persisted across the tmpfs root.
    "dms-greeter cache is persisted" = builtins.elem "/var/lib/dms-greeter" dirNames;

    # per-user home persistence (itera.impermanence.homes, on by default)
    "user home .config persisted by default" = builtins.elem ".config" (userDirs "testuser");
    "user home .local/share persisted by default" = builtins.elem ".local/share" (userDirs "testuser");
    "user home .cache persisted by default" = builtins.elem ".cache" (userDirs "testuser");
    "user home Documents persisted by default" = builtins.elem "Documents" (userDirs "testuser");

    # core-boot batteries (activated by itera.enable)
    "systemd-boot is enabled" = cfg.boot.loader.systemd-boot.enable;
    "EFI variables are touchable" = cfg.boot.loader.efi.canTouchEfiVariables;
    "systemd initrd is enabled" = cfg.boot.initrd.systemd.enable;
    "flakes are enabled" = builtins.elem "flakes" cfg.nix.settings.experimental-features;
    "unfree is allowed" = cfg.nixpkgs.config.allowUnfree;
    "stateVersion is set" = cfg.system.stateVersion == "25.05";
    "time zone is set" = cfg.time.timeZone == "America/Chicago";
    "default locale is set" = cfg.i18n.defaultLocale == "en_US.UTF-8";
    "NetworkManager is enabled" = cfg.networking.networkmanager.enable;
    "hostname is set" = cfg.networking.hostName == "itera";

    # hardening (nix-mineral, auto-on with itera.enable)
    "nix-mineral hardening is enabled" = cfg.nix-mineral.enable;
    # Kicksecure's static generic machine-id is disabled so hosts get a unique,
    # persisted id (and to avoid the systemd-machine-id-commit boot failure).
    "machine-id is not a static generic id" = !(cfg.environment.etc ? "machine-id");
    "machine-id commit is disabled under hardening" =
      cfg.systemd.services.systemd-machine-id-commit.enable == false;
    # ...but the id is still persisted (via activation script) so it stays stable
    # across reboots instead of regenerating and churning the NM MAC / DHCP IP.
    "machine-id is persisted despite masked commit" =
      cfg.system.activationScripts ? iteraPersistMachineId;
    # Stable MAC (not nix-mineral's per-connection random) so the DHCP lease/IP
    # stays constant across reboots.
    "MAC address is stable, not randomized" =
      cfg.networking.networkmanager.wifi.macAddress == "stable"
      && cfg.networking.networkmanager.ethernet.macAddress == "stable";
    "nix-mineral random-mac is disabled" = cfg.nix-mineral.settings.network.random-mac == false;

    # binary-cache battery (auto-on with itera.enable)
    "nix-community substituter is configured" =
      builtins.elem "https://nix-community.cachix.org" cfg.nix.settings.extra-substituters;

    # garbage-collection battery (auto-on with itera.enable)
    "gc is automatic" = cfg.nix.gc.automatic;
    "gc deletes old generations" = cfg.nix.gc.options == "--delete-older-than 14d";
    "store optimise is automatic" = cfg.nix.optimise.automatic;

    # hibernation resume wiring (itera.disko.resume, gated on swap being set)
    "resume is gated off without a swap partition" = cfg.itera.disko.resume == false;
    "resume defaults on when a swap partition is set" = swapOn.itera.disko.resume == true;
    "no resumeDevice without a swap partition" = cfg.boot.resumeDevice == "";
    "swap partition registers a resume device" = swapOn.boot.resumeDevice != "";
    "resumeDevice matches a real swap device" = builtins.any (
      s: s.device == swapOn.boot.resumeDevice
    ) swapOn.swapDevices;
    "resume=<dev> reaches the kernel command line" =
      builtins.elem "resume=${swapOn.boot.resumeDevice}" swapOn.boot.kernelParams;
    "itera.disko.resume = false creates swap without a resume device" =
      swapNoResume.swapDevices != [ ] && swapNoResume.boot.resumeDevice == "";

    # NVIDIA battery (itera.nvidia, opt-in)
    "nvidia is off by default" = cfg.itera.nvidia.enable == false;
    "nvidia driver not selected by default" =
      !(builtins.elem "nvidia" cfg.services.xserver.videoDrivers);
    "nvidia enables the nvidia video driver" =
      builtins.elem "nvidia" nvidiaOn.services.xserver.videoDrivers;
    "nvidia enables hardware.graphics" = nvidiaOn.hardware.graphics.enable;
    "nvidia enables modesetting" = nvidiaOn.hardware.nvidia.modesetting.enable;
    "nvidia uses the open kernel module by default" = nvidiaOn.hardware.nvidia.open;
    "nvidia PRIME bus IDs are wired" =
      nvidiaOn.hardware.nvidia.prime.intelBusId == "PCI:0:2:0"
      && nvidiaOn.hardware.nvidia.prime.nvidiaBusId == "PCI:1:0:0";
    "nvidia PRIME offload is on by default" = nvidiaOn.hardware.nvidia.prime.offload.enable;
    # Under PRIME offload, GBM_BACKEND must NOT be forced globally.
    "nvidia PRIME offload does not force GBM_BACKEND globally" =
      !(nvidiaOn.environment.variables ? GBM_BACKEND);
    "nvidia sets the wlroots cursor workaround" =
      nvidiaOn.environment.variables.WLR_NO_HARDWARE_CURSORS == "1";
  };

in
mkCheckDrv "itera-disko-impermanence-eval" checks
