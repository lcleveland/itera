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

  # gaming battery (itera.gaming, opt-in). Enabling it must re-enable 32-bit
  # (i686) execution — hardening's default `ia32_emulation=0` otherwise breaks
  # the 32-bit binaries Steam/Proton ship.
  gamingOn = mkEval { itera.gaming.enable = true; };

  # dev tooling battery (itera.dev) is on by default; a second eval with it off to
  # assert it's gated.
  devOff = mkEval { itera.dev.enable = false; };
  hasPkg = c: n: builtins.any (p: lib.getName p == n) c.environment.systemPackages;

  # Reading .source forces the derivation the full system build produces, so this
  # catches an /etc/gitconfig definition collision that a plain option read hides.
  renderedGitconfig = builtins.readFile cfg.environment.etc.gitconfig.source;

  subvolumes = cfg.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  persistence = cfg.environment.persistence."/persist";

  # impermanence coerces string entries into attrsets ({ file = ...; } /
  # { directory = ...; }); tolerate either shape.
  fileNames = map (f: f.file or f) persistence.files;
  dirNames = map (d: d.directory or d) persistence.directories;
  userDirs = name: map (d: d.directory or d) persistence.users.${name}.directories;
  userFiles = name: map (f: f.file or f) persistence.users.${name}.files;

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
    # Bluetooth is on by default (itera.enable), so BlueZ device pairings survive
    # the wiped root rather than needing a re-pair every boot.
    "bluetooth pairings are persisted" = builtins.elem "/var/lib/bluetooth" dirNames;
    # Bluetooth powers the adapter on at boot by default — the Kicksecure
    # AutoEnable=false default is overridden so the radio isn't dark despite
    # powerOnBoot.
    "bluetooth auto-enables the adapter by default" =
      cfg.hardware.bluetooth.settings.Policy.AutoEnable == true;

    # dev tooling battery (itera.dev, on by default): git is installed system-wide
    # so a fresh host can work on a Nix config; gated off with the battery.
    "git is installed by default" = hasPkg cfg "git";
    "gh is installed by default" = hasPkg cfg "gh";
    "dev tooling is gated off when disabled" = !(hasPkg devOff "git");
    # gh is wired up as git's HTTPS credential helper whenever it ships in the
    # battery, so `gh auth login` transparently authenticates git too.
    # gh is wired up as git's HTTPS credential helper whenever it ships in the
    # battery. Read the rendered /etc/gitconfig (forcing the .source the full
    # system build resolves — a plain option read would miss the collision) and
    # assert it both carries the helper and preserves nix-mineral's git hardening,
    # since the dev battery takes /etc/gitconfig over from nix-mineral to add it.
    "gh is git's credential helper by default" =
      lib.hasInfix ''[credential "https://github.com"]'' renderedGitconfig
      && lib.hasInfix "gh auth git-credential" renderedGitconfig;
    "git hardening survives the credential-helper takeover" =
      lib.hasInfix "fsckobjects = true" renderedGitconfig
      && lib.hasInfix "symlinks = false" renderedGitconfig;

    # password persistence (itera.impermanence.passwords, on by default): copy
    # /etc/shadow to/from /persist so `passwd` changes survive the tmpfs root —
    # by copy, never a bind mount (which breaks NixOS's atomic-rename writes).
    "shadow restore runs before the users activation script" =
      builtins.elem "iteraPersistShadow" cfg.system.activationScripts.users.deps;
    "shadow persistence activation script present" = cfg.system.activationScripts ? iteraPersistShadow;
    "shadow persistence shutdown service present" = cfg.systemd.services ? "itera-persist-shadow";

    # per-user home persistence (itera.impermanence.homes, on by default)
    "user home .config persisted by default" = builtins.elem ".config" (userDirs "testuser");
    "user home .local/share persisted by default" = builtins.elem ".local/share" (userDirs "testuser");
    "user home .local/state persisted by default" = builtins.elem ".local/state" (userDirs "testuser");
    "user home .cache persisted by default" = builtins.elem ".cache" (userDirs "testuser");
    "user home .ssh persisted by default" = builtins.elem ".ssh" (userDirs "testuser");
    # Claude Code's credentials/settings live in ~/.claude and its account/onboarding
    # state in ~/.claude.json — persist both so the login survives the tmpfs root.
    "user home .claude persisted by default" = builtins.elem ".claude" (userDirs "testuser");
    "user home .claude.json persisted by default" = builtins.elem ".claude.json" (userFiles "testuser");
    "user home Documents persisted by default" = builtins.elem "Documents" (userDirs "testuser");
    # Browser battery is on by default, so the LibreWolf profile (~/.librewolf) —
    # bookmarks/logins/history — survives the tmpfs root.
    "user home .librewolf persisted when browser on" = builtins.elem ".librewolf" (userDirs "testuser");

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

    # garbage-collection battery (auto-on with itera.enable). By default nh clean
    # owns scheduled GC, so the nix.gc timer steps aside (see nh-eval.nix for the
    # hand-off); the store-optimise pass runs regardless.
    "nh clean owns GC, so nix.gc timer is off by default" = !cfg.nix.gc.automatic;
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

    # gaming battery (itera.gaming, opt-in) — Steam + 32-bit support
    "gaming enables steam" = gamingOn.programs.steam.enable;
    "gaming enables 32-bit GL" = gamingOn.hardware.graphics.enable32Bit;
    # 32-bit (i686) execution stays on system-wide (not gated on gaming), so a
    # config pulling in 32-bit closures can always be built — hardening keeps
    # multilib on, i.e. never sets `ia32_emulation=0`. See hardening.nix.
    "ia32 emulation stays enabled by default" =
      !(builtins.elem "ia32_emulation=0" cfg.boot.kernelParams);
    "ia32 emulation stays enabled with gaming" =
      !(builtins.elem "ia32_emulation=0" gamingOn.boot.kernelParams);
  };

in
mkCheckDrv "itera-disko-impermanence-eval" checks
