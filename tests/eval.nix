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

  # Same, with the opt-out that KEEPS ~/Downloads across reboots (clearing is on by
  # default), to assert the boot-time clear service drops out when disabled.
  clearDownloadsOff = mkEval {
    itera.users.testuser = { };
    itera.impermanence.homes.clearDownloadsOnBoot = false;
  };

  # Desktop off → power-profiles-daemon is not pulled in, so the profile-persist
  # service and its persist entry must both drop out (gated on the daemon switch).
  desktopOff = mkEval { itera.desktop.dankMaterialShell.enable = false; };
  desktopOffDirNames = map (
    d: d.directory or d
  ) desktopOff.environment.persistence."/persist".directories;

  # Two extra evals to exercise the hibernation resume wiring (itera.disko.resume):
  # a swap partition sized for hibernation, and the same with resume opted out.
  swapOn = mkEval { itera.disko.swapSize = "16G"; };
  swapNoResume = mkEval {
    itera.disko.swapSize = "16G";
    itera.disko.resume = false;
  };

  # Flakes opted out → channels come back, since a channel-based system is then
  # the only way to resolve `<nixpkgs>`.
  flakesOff = mkEval { itera.nix.flakes.enable = false; };

  # Full-disk encryption (itera.disko.encryption, opt-in, default off). Enable it
  # alongside a swap partition so this eval exercises BOTH LUKS containers (root +
  # swap) and the resume-through-LUKS wiring.
  encryptionOn = mkEval {
    itera.disko.encryption.enable = true;
    itera.disko.swapSize = "16G";
  };

  # TPM2 auto-unlock layered on encryption (itera.disko.encryption.tpm2, opt-in). A
  # swap partition too, so this exercises the crypttab wiring on BOTH containers.
  tpm2On = mkEval {
    itera.disko = {
      encryption = {
        enable = true;
        tpm2.enable = true;
      };
      swapSize = "16G";
    };
  };

  # Extra data drives (itera.disko.dataDrives). itera OWNS these disks so encryption
  # applies uniformly, so three variants exercise the matrix: an encrypted btrfs
  # drive with TPM2 on (must join the boot disk's LUKS + tpm2-device=auto flow), a
  # plain encryption-off drive (no LUKS wrapper), and an ext4 drive (fsType-specific
  # format + mountOptions).
  dataDrivesEncTpm2 = mkEval {
    itera.disko.encryption = {
      enable = true;
      tpm2.enable = true;
    };
    itera.disko.dataDrives.extra = {
      device = "/dev/vdb";
      mountpoint = "/data";
    };
  };
  dataDrivesPlain = mkEval {
    itera.disko.dataDrives.extra = {
      device = "/dev/vdb";
      mountpoint = "/data";
    };
  };
  dataDrivesExt4 = mkEval {
    itera.disko.dataDrives.extra = {
      device = "/dev/vdb";
      mountpoint = "/data";
      fsType = "ext4";
    };
  };

  # Runtime auto-claim of blank disks (itera.disko.autoClaim, opt-in). Assert the
  # boot service is gated and that its environment reflects fsType/encryption/keyfile.
  autoClaimOn = mkEval { itera.disko.autoClaim.enable = true; };
  autoClaimEncrypted = mkEval {
    itera.disko.encryption.enable = true;
    itera.disko.autoClaim.enable = true;
  };
  autoClaimExt4 = mkEval {
    itera.disko.autoClaim = {
      enable = true;
      fsType = "ext4";
    };
  };
  claimEnv = c: c.systemd.services.itera-claim-disks.environment;

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

  # Same battery on a host that has relaxed yama, to assert the ptrace warning
  # is conditional and not a permanent nag.
  gamingYamaRelaxed = mkEval {
    itera.gaming.enable = true;
    nix-mineral.settings.system.yama = "relaxed";
  };

  # caching resolver (itera.networking.resolved, on by default); a second eval
  # with it off to assert systemd-resolved is gated, and one with AAAA
  # suppression opted out (on by default) to assert the no-aaaa gate.
  resolvedOff = mkEval { itera.networking.resolved.enable = false; };
  suppressAAAAOff = mkEval { itera.networking.resolved.suppressAAAA = false; };

  # dev tooling battery (itera.dev) is on by default; a second eval with it off to
  # assert it's gated.
  devOff = mkEval { itera.dev.enable = false; };
  hasPkg = c: n: builtins.any (p: lib.getName p == n) c.environment.systemPackages;

  # Reading .source forces the derivation the full system build produces, so this
  # catches an /etc/gitconfig definition collision that a plain option read hides.
  renderedGitconfig = builtins.readFile cfg.environment.etc.gitconfig.source;

  subvolumes = cfg.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  persistence = cfg.environment.persistence."/persist";

  # Partition set for a given evaluated config, and the encrypted root/swap
  # containers (used by the full-disk-encryption checks below).
  partitions = c: c.disko.devices.disk.main.content.partitions;
  encRoot = (partitions encryptionOn).root.content;
  encSwap = (partitions encryptionOn).swap.content;
  # The `extra` data drive's single-partition content (a LUKS wrapper when
  # encrypted, else the bare filesystem) — used by the dataDrives checks below.
  dataPart = c: c.disko.devices.disk.extra.content.partitions.data.content;

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

    # power-profiles-daemon (on via the default DMS desktop) does not persist its
    # active profile, so itera's power battery saves it under /var/lib and this
    # persists that across the tmpfs root — otherwise the bar's profile choice
    # resets to `balanced` every boot. Service and persist entry are both gated on
    # the daemon: present with the desktop on, gone with it off.
    "power profile state is persisted" = builtins.elem "/var/lib/itera-power-profile" dirNames;
    "power profile persist service present" = cfg.systemd.services ? "itera-power-profile-persist";
    # It must be a companion of the daemon, never wanted by multi-user.target: the
    # upstream PPD unit is `After=multi-user.target`, so a multi-user.target tie +
    # `After=power-profiles-daemon.service` is an ordering cycle that makes systemd
    # delete the start job (the unit then never runs on boot or shutdown).
    "power profile persist service is wanted by the daemon (no ordering cycle)" =
      cfg.systemd.services."itera-power-profile-persist".wantedBy == [ "power-profiles-daemon.service" ];
    "power profile persist service gated off without the daemon" =
      !(desktopOff.systemd.services ? "itera-power-profile-persist");
    "power profile state not persisted without the daemon" =
      !(builtins.elem "/var/lib/itera-power-profile" desktopOffDirNames);
    # Bluetooth powers the adapter on at boot by default — the Kicksecure
    # AutoEnable=false default is overridden so the radio isn't dark despite
    # powerOnBoot.
    "bluetooth auto-enables the adapter by default" =
      cfg.hardware.bluetooth.settings.Policy.AutoEnable == true;

    # caching resolver (itera.networking.resolved, on by default): systemd-resolved
    # runs as a caching stub, NetworkManager feeds it the network's DNS, and it's
    # gated when disabled. DNSSEC must stay off (nix-mineral would force it strict,
    # breaking split-horizon/roaming) — see networking.nix.
    "caching resolver enables systemd-resolved by default" = cfg.services.resolved.enable;
    "networkmanager hands dns to systemd-resolved" =
      cfg.networking.networkmanager.dns == "systemd-resolved";
    "resolved dnssec is not forced strict" =
      cfg.services.resolved.settings.Resolve.DNSSEC == false
      && cfg.nix-mineral.settings.misc.dnssec == false;
    "caching resolver is gated off when disabled" = !resolvedOff.services.resolved.enable;
    # AAAA suppression is on by default (opt-out): sets glibc's no-aaaa option
    # on the nsncd daemon, and is gated when disabled. See networking.nix.
    "AAAA suppression sets no-aaaa on nscd by default" =
      cfg.systemd.services.nscd.environment.RES_OPTIONS == "no-aaaa";
    "AAAA suppression is gated off when disabled" =
      !(suppressAAAAOff.systemd.services.nscd.environment ? RES_OPTIONS);

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
    # ~/Downloads persisted so large downloads land on disk, not the size-capped tmpfs root.
    "user home Downloads persisted by default" = builtins.elem "Downloads" (userDirs "testuser");
    # ~/Pictures persisted on the same reasoning, but nothing clears it on boot.
    "user home Pictures persisted by default" = builtins.elem "Pictures" (userDirs "testuser");
    # clearDownloadsOnBoot (opt-out, default on): a boot-time service empties
    # ~/Downloads unless disabled — Downloads stays persisted either way.
    "clear-downloads service present by default" =
      (cfg.systemd.services ? "itera-clear-downloads")
      && builtins.elem "Downloads" (
        map (d: d.directory or d) cfg.environment.persistence."/persist".users.testuser.directories
      );
    "clear-downloads service absent when clearDownloadsOnBoot off" =
      !(clearDownloadsOff.systemd.services ? "itera-clear-downloads")
      && builtins.elem "Downloads" (
        map (
          d: d.directory or d
        ) clearDownloadsOff.environment.persistence."/persist".users.testuser.directories
      );
    # Vivaldi's profile lives at ~/.config/vivaldi, covered by the curated
    # `.config` home dir, so bookmarks/logins/history survive the tmpfs root
    # without a browser-specific persistence entry.
    "user home .config persisted (covers vivaldi profile)" = builtins.elem ".config" (
      userDirs "testuser"
    );

    # core-boot batteries (activated by itera.enable)
    "systemd-boot is enabled" = cfg.boot.loader.systemd-boot.enable;
    "EFI variables are touchable" = cfg.boot.loader.efi.canTouchEfiVariables;
    "systemd initrd is enabled" = cfg.boot.initrd.systemd.enable;
    "flakes are enabled" = builtins.elem "flakes" cfg.nix.settings.experimental-features;
    # Channels off under flakes, so the never-created channel dir stays out of
    # NIX_PATH and stops warning on every eval — but `<nixpkgs>` still resolves,
    # via the registry pin nixpkgs sets for flake-built systems.
    "nix channels are disabled under flakes" = cfg.nix.channel.enable == false;
    "channel dir is not on the nix search path" =
      !(builtins.elem "/nix/var/nix/profiles/per-user/root/channels" cfg.nix.nixPath);
    "nixpkgs still resolves via the flake registry" =
      builtins.elem "nixpkgs=flake:nixpkgs" cfg.nix.nixPath;
    "channels return when flakes are opted out" = flakesOff.nix.channel.enable;
    "unfree is allowed" = cfg.nixpkgs.config.allowUnfree;
    "stateVersion is set" = cfg.system.stateVersion == "25.05";
    "time zone is set" = cfg.time.timeZone == "America/Chicago";
    "default locale is set" = cfg.i18n.defaultLocale == "en_US.UTF-8";
    "NetworkManager is enabled" = cfg.networking.networkmanager.enable;
    "hostname is set" = cfg.networking.hostName == "itera";

    # hardening (nix-mineral, auto-on with itera.enable)
    "nix-mineral hardening is enabled" = cfg.nix-mineral.enable;
    # Kicksecure's static generic machine-id is never applied, so hosts get a
    # unique, persisted id (and avoid the systemd-machine-id-commit boot
    # failure). itera gets this by leaving nix-mineral's deprecated, now-inert
    # `settings.etc.generic-machine-id` unset — see hardening.nix.
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

    # full-disk encryption (itera.disko.encryption, opt-in, default off)
    "encryption is off by default" = cfg.itera.disko.encryption.enable == false;
    "root is plain btrfs when encryption is off" = (partitions cfg).root.content.type == "btrfs";
    "no initrd luks devices when encryption is off" = cfg.boot.initrd.luks.devices == { };
    # Enabled: the btrfs root is wrapped in a LUKS container named cryptroot, with
    # the btrfs (and its /persist subvolume) living inside the decrypted mapper.
    "encryption wraps root in a luks container" =
      encRoot.type == "luks" && encRoot.name == "cryptroot" && encRoot.content.type == "btrfs";
    "encrypted root still carries the /persist subvolume" = encRoot.content.subvolumes ? "/persist";
    # The swap partition is likewise wrapped (cryptswap), so the hibernation image
    # written to it is encrypted.
    "encryption wraps swap in a luks container" =
      encSwap.type == "luks" && encSwap.name == "cryptswap" && encSwap.content.type == "swap";
    # disko auto-emits a boot.initrd.luks.devices entry per container (initrdUnlock)
    # so both unlock at boot, and allowDiscards passes through to that entry.
    "encryption registers a cryptroot initrd luks device" =
      encryptionOn.boot.initrd.luks.devices ? "cryptroot";
    "encryption registers a cryptswap initrd luks device" =
      encryptionOn.boot.initrd.luks.devices ? "cryptswap";
    "encryption passes allowDiscards through to the initrd luks device" =
      encryptionOn.boot.initrd.luks.devices.cryptroot.allowDiscards == true;
    # Encryption auto-enables USB-in-initrd so a USB keyboard can type the passphrase.
    "encryption auto-enables usb support in the initrd" =
      encryptionOn.itera.hardware.initrd.usbSupport == true;
    # Resume through LUKS: the swap type inside the container resolves its device to
    # the mapper, so boot.resumeDevice points at the decrypted /dev/mapper/cryptswap
    # (not the raw partition) and hibernation still resumes.
    "encrypted swap resume device is the luks mapper" =
      encryptionOn.boot.resumeDevice == "/dev/mapper/cryptswap";

    # TPM2 auto-unlock (itera.disko.encryption.tpm2, opt-in, default off)
    "tpm2 auto-unlock is off by default" = cfg.itera.disko.encryption.tpm2.enable == false;
    "tpm2 pcrs default to 7 (Secure Boot state)" = cfg.itera.disko.encryption.tpm2.pcrs == "7";
    # Off: no tpm2-device crypttab option on the (encryption-only) containers.
    "no tpm2 crypttab option when tpm2 unlock is off" =
      !(builtins.elem "tpm2-device=auto" encryptionOn.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts);
    # On: both containers get tpm2-device=auto so the systemd initrd unseals them.
    "tpm2 unlock wires tpm2-device=auto onto the root container" =
      builtins.elem "tpm2-device=auto" tpm2On.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts;
    "tpm2 unlock wires tpm2-device=auto onto the swap container" =
      builtins.elem "tpm2-device=auto" tpm2On.boot.initrd.luks.devices.cryptswap.crypttabExtraOpts;
    # The TPM kernel modules must be in the initrd for the device node in stage 1.
    "tpm2 unlock pulls the tpm_tis module into the initrd" =
      builtins.elem "tpm_tis" tpm2On.boot.initrd.availableKernelModules;
    # USB-in-initrd stays force-on even with TPM2: the happy path types nothing, but
    # the recovery-passphrase fallback (fired on a PCR change) still needs a keyboard
    # in early boot, so dropping it would risk a lockout on USB-keyboard machines.
    "tpm2 unlock keeps usb support forced on for the recovery prompt" =
      tpm2On.itera.hardware.initrd.usbSupport == true;
    # The enrollment helper is shipped when TPM2 unlock is on.
    "tpm2 unlock ships the itera-tpm2-enroll helper" = hasPkg tpm2On "itera-tpm2-enroll";

    # extra data drives (itera.disko.dataDrives) — itera owns them so encryption applies
    "no data drives by default" = cfg.itera.disko.dataDrives == { };
    "no extra disk emitted without data drives" = !(cfg.disko.devices.disk ? "extra");
    # Plain (encryption off): a flat btrfs filesystem mounted at the drive's mountpoint,
    # no LUKS wrapper, carrying the btrfs zstd mount options.
    "data drive is plain btrfs when encryption is off" =
      (dataPart dataDrivesPlain).type == "btrfs" && (dataPart dataDrivesPlain).mountpoint == "/data";
    "plain data drive gets the btrfs zstd mount options" =
      builtins.elem "compress=zstd" (dataPart dataDrivesPlain).mountOptions;
    # ext4 variant: the generic filesystem type + ext4 format, and NO btrfs-only
    # compress option (which would break an ext4 mount).
    "ext4 data drive uses the filesystem type with ext4 format" =
      (dataPart dataDrivesExt4).type == "filesystem" && (dataPart dataDrivesExt4).format == "ext4";
    "ext4 data drive omits the btrfs compress mount option" =
      !(builtins.elem "compress=zstd" (dataPart dataDrivesExt4).mountOptions);
    # Encrypted: wrapped in a uniquely-named cryptdata-<name> LUKS container, with the
    # btrfs inside, still mounted at /data.
    "encryption wraps the data drive in a cryptdata luks container" =
      (dataPart dataDrivesEncTpm2).type == "luks"
      && (dataPart dataDrivesEncTpm2).name == "cryptdata-extra"
      && (dataPart dataDrivesEncTpm2).content.type == "btrfs"
      && (dataPart dataDrivesEncTpm2).content.mountpoint == "/data";
    "encryption registers a cryptdata initrd luks device" =
      dataDrivesEncTpm2.boot.initrd.luks.devices ? "cryptdata-extra";
    # ...and it joins the same single TPM2 unlock flow as the boot disk.
    "tpm2 unlock wires tpm2-device=auto onto the data container" =
      builtins.elem "tpm2-device=auto"
        dataDrivesEncTpm2.boot.initrd.luks.devices."cryptdata-extra".crypttabExtraOpts;
    # The user-facing outcome: disko turns the drive into a real NixOS fileSystems
    # mount at its mountpoint, off the decrypted mapper, btrfs, and NOT neededForBoot
    # (it mounts in stage 2, independent of the impermanence tmpfs root).
    "data drive produces a /data fileSystems mount off the luks mapper" =
      dataDrivesEncTpm2.fileSystems ? "/data"
      && dataDrivesEncTpm2.fileSystems."/data".device == "/dev/mapper/cryptdata-extra"
      && dataDrivesEncTpm2.fileSystems."/data".fsType == "btrfs";
    "data drive mount is not neededForBoot" =
      (dataDrivesEncTpm2.fileSystems."/data".neededForBoot or false) == false;

    # runtime auto-claim (itera.disko.autoClaim, opt-in, default off)
    "autoClaim is off by default" = cfg.itera.disko.autoClaim.enable == false;
    "no claim service by default" = !(cfg.systemd.services ? "itera-claim-disks");
    "autoClaim installs the boot claim service" = autoClaimOn.systemd.services ? "itera-claim-disks";
    "claim service is a oneshot that stays active" =
      autoClaimOn.systemd.services.itera-claim-disks.serviceConfig.Type == "oneshot"
      && autoClaimOn.systemd.services.itera-claim-disks.serviceConfig.RemainAfterExit;
    # Encryption follows itera.disko.encryption, surfaced to the script via env.
    "claim service reports encryption off by default" =
      (claimEnv autoClaimOn).ITERA_CLAIM_ENCRYPT == "0";
    "autoClaim + encryption tells the service to encrypt" =
      (claimEnv autoClaimEncrypted).ITERA_CLAIM_ENCRYPT == "1";
    # Under impermanence the LUKS keyfile lives on the persistent root.
    "autoClaim keyfile lives under the persist root" =
      (claimEnv autoClaimEncrypted).ITERA_CLAIM_KEYFILE == "/persist/itera/claim-disks.key";
    # fsType drives both the format and the (btrfs-only) compress mount option.
    "autoClaim defaults to btrfs with zstd mount options" =
      (claimEnv autoClaimOn).ITERA_CLAIM_FSTYPE == "btrfs"
      && lib.hasInfix "compress=zstd" (claimEnv autoClaimOn).ITERA_CLAIM_MOUNTOPTS;
    "autoClaim ext4 drops the btrfs compress option" =
      (claimEnv autoClaimExt4).ITERA_CLAIM_FSTYPE == "ext4"
      && !(lib.hasInfix "compress=zstd" (claimEnv autoClaimExt4).ITERA_CLAIM_MOUNTOPTS);

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
    # The clipboard bridge (default on with the desktop) injects the X11 clipboard
    # tools into Steam's FHS container so Proton games can reach the clipboard —
    # only when Steam is actually enabled (here, via the gaming battery).
    "gaming injects wl-clipboard-x11 into steam" = builtins.any (
      p: lib.getName p == "wl-clipboard-x11"
    ) gamingOn.programs.steam.extraPackages;
    "gaming injects xdotool into steam" = builtins.any (
      p: lib.getName p == "xdotool"
    ) gamingOn.programs.steam.extraPackages;
    # ...and without Steam there is no injection to make (extraPackages stays empty
    # of the clipboard tools on the default, gaming-off desktop).
    "no steam clipboard injection without steam" =
      !(builtins.any (p: lib.getName p == "wl-clipboard-x11") cfg.programs.steam.extraPackages);
    # Hardening leaves yama at "restricted" (ptrace_scope 3), which blocks the
    # ptrace Wine/Proton does on its own children. The gaming battery must warn
    # about that rather than silently relax it — and must go quiet once a host
    # has actually relaxed it.
    "hardening keeps yama restricted by default" = cfg.nix-mineral.settings.system.yama == "restricted";
    "gaming warns about the ptrace/yama conflict" = builtins.any (
      w: lib.hasInfix "ptrace_scope" w
    ) gamingOn.warnings;
    "gaming is quiet once yama is relaxed" =
      !(builtins.any (w: lib.hasInfix "ptrace_scope" w) gamingYamaRelaxed.warnings);
  };

in
mkCheckDrv "itera-disko-impermanence-eval" checks
