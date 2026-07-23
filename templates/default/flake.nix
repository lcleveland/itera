{
  description = "A NixOS configuration built on itera + hjem";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # hjem manages your $HOME. itera's home modules are class-`hjem` submodules,
    # so itera MUST share this exact hjem (see `follows` below) — otherwise
    # evaluation breaks with confusing submodule-class errors.
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs"; # keep hjem on your channel, one nixpkgs
    };

    itera = {
      url = "github:lcleveland/itera";
      inputs.nixpkgs.follows = "nixpkgs"; # build itera against your channel
      inputs.hjem.follows = "hjem"; # CRITICAL: share one hjem
    };
  };

  outputs =
    { nixpkgs, itera, ... }:
    {
      # One installer for every host in this flake, meant to be run from a NixOS
      # live ISO. It picks a host + disk, confirms the wipe, and hands off to
      # disko-install — and, for hosts that opt into itera.disko.encryption, drives
      # the LUKS passphrase and enrolls TPM2 auto-unlock in the same pass, so an
      # encrypted host is hands-free from first boot. No hand-written install script:
      #
      #   sudo nix run github:me/myconfig#installer            # menus for host + disk
      #   sudo nix run github:me/myconfig#installer -- myhost /dev/nvme0n1
      #
      # Run a local clone with:  sudo ITERA_INSTALL_FLAKE=. nix run .#installer
      packages.x86_64-linux.installer =
        itera.lib.mkInstaller (import nixpkgs { system = "x86_64-linux"; })
          {
            flake = "github:me/myconfig"; # CHANGE ME — where `nix run <flake>#installer` fetches from
          };

      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # A single import: pulls in hjem and wires itera's home layer for you.
          # There is NO hardware-configuration.nix — itera supplies the whole
          # hardware layer (kernel modules, microcode, firmware via
          # `itera.hardware`) and disko owns the disk layout (`itera.disko`).
          itera.nixosModules.default

          {
            nixpkgs.overlays = [ itera.overlays.default ];

            # itera's opinionated system defaults are opt-out — on by default, so
            # this import alone gives you a bootable system: systemd-boot on the
            # ESP, the systemd initrd, a broad set of hardware modules, flakes
            # enabled, a pinned stateVersion, a locale, NetworkManager, hardening,
            # and the desktop. Every value is a mkDefault, so override any of
            # them. Set `itera.enable = false` to turn the whole layer off.
            itera = {
              # Override individual core defaults as needed:
              networking.hostName = "myhost";
              #   locale.timeZone = "Europe/London";
              #   locale.defaultLocale = "en_GB.UTF-8";
              #   boot.kernelPackages = pkgs.linuxPackages_latest;

              # Pin the NixOS release your stateful data matches. Set this ONCE
              # at install time to the release you installed from, then never
              # change it.
              nix.stateVersion = "25.05";

              # Where `itera rebuild`/`update` build this host from, and which
              # configuration it is. Point `update.flake` at your config — a
              # remote URL or a persisted local checkout — so `itera update`
              # (and bare `nh os switch`) works with no args after install;
              # otherwise nh looks for /etc/nixos/flake.nix, which itera doesn't
              # create. `update` uses --refresh for a remote flake, --update for
              # a local path. `update.configuration` defaults to the hostname;
              # set it if your flake's nixosConfigurations attribute differs.
              #   update.flake = "github:me/dream"; # or "/home/alice/Documents/itera-config"
              #   update.configuration = "dream";

              # Hardware layer — replaces a generated hardware-configuration.nix.
              # The initrd kernel-module default boots virtually any modern UEFI
              # x86 machine; you normally only pick a CPU vendor.
              hardware.cpu = "auto"; # or "intel" / "amd"
              #   hardware.initrd.availableKernelModules = [ ... ]; # exotic controller

              # nixos-facter hardware detection is AUTOMATIC (on by default):
              # `itera rebuild` regenerates /var/lib/itera/facter.json on this
              # machine and builds with it (impurely) — nothing to commit. An
              # NVIDIA GPU in the report auto-enables `itera.nvidia`. Opt out with:
              #   hardware.facter.autoGenerate = false; # or use a committed report:
              #   hardware.facter.reportPath = ./facter.json;
              #   hardware.facter.autoNvidia = false;   # keep nouveau instead

              # Declarative disk layout + ephemeral (tmpfs) root, bundled with
              # itera (no extra inputs). Both are ON by default. disko WIPES the
              # target device and has no safe default, so you MUST point it at a
              # disk — the build fails with an assertion until you do. This is the
              # one genuinely per-machine value.
              disko.device = "/dev/nvme0n1"; # CHANGE ME — disko WIPES this disk
              #   disko.swapSize = "8G";       # optional swap partition. Size it
              #     >= your RAM and it doubles as the hibernation resume device, so
              #     `systemctl hibernate` works out of the box (disko wires
              #     boot.resumeDevice). Set `disko.resume = false` for swap without
              #     hibernation.
              #   disko.encryption.enable = true; # LUKS full-disk encryption of the
              #     btrfs root (/, /nix, /persist) AND swap — so data at rest and the
              #     hibernation image are encrypted (the ESP stays unencrypted). Opt-in.
              #     You type the passphrase at every boot; itera's systemd initrd
              #     unlocks root + swap with a SINGLE prompt, and turns on
              #     itera.hardware.initrd.usbSupport so a USB keyboard works at that
              #     prompt (set it back to false only if your keyboard already works
              #     in stage 1). The `installer` package below drives the passphrase
              #     for you at install time; a manual disko-install prompts instead.
              #   disko.encryption.tpm2.enable = true; # passwordless auto-unlock from
              #     the TPM2 (no passphrase on a trusted boot; the passphrase stays as
              #     a recovery fallback). Pair with `secureBoot.enable = true` for it
              #     to also stop a powered-on thief. To enroll the TPM2 keyslot during
              #     install (so the FIRST boot is already hands-free), give the
              #     installer a scratch key path it fills and shreds:
              #       disko.encryption.passwordFile = "/tmp/itera-luks.key"; # install-time only
              #     Without it you just run `sudo itera-tpm2-enroll` once after first boot.
              #   impermanence.directories = [ "/var/lib/tailscale" ];

              # Advanced: to manage partitioning yourself (e.g. a pre-partitioned
              # machine you can't wipe, or dual-boot), turn both off and add your
              # own ./hardware-configuration.nix to the modules list above:
              #   hardware.enable = false;
              #   disko.enable = false;
              #   impermanence.enable = false;

              # Ecosystem batteries. ON by default (opt-out):
              #   secrets           agenix declarative secrets (inert until used):
              #     secrets.secrets.wifi-psk.file = ./secrets/wifi-psk.age;
              #   nixIndex          command-not-found + `comma` (`,`)
              #   virtualisation    QEMU/KVM via libvirt + virt-manager GUI (add
              #     "libvirtd" to the user's extraGroups below; set hardware.cpu
              #     to "intel"/"amd" for KVM acceleration)
              #   desktop.fileManager   Nemo file manager
              #   desktop.theme         dark mode for GTK/Flatpak apps
              #                         (theme.dark = false for a light session)
              #
              # OFF by default (opt-in):
              #   secureBoot.enable = true;      # then: sbctl create-keys && sbctl enroll-keys
              #   desktop.flatpak.enable = true; # declarative Flatpak (Flathub)
              #   desktop.flatpak.packages = [ "com.brave.Browser" ];
            };

            # A login user via itera's account battery. `itera.users.<name>`
            # creates the normal-user account AND enables hjem for it, so the
            # user inherits every itera home battery and its system-wide defaults
            # (DankMaterialShell settings, mango keybinds, …). CHANGE ME before
            # deploying: pick your username and set a real password (prefer
            # `hashedPassword` / `hashedPasswordFile` set on `users.users.alice`,
            # which merges with this — over `initialPassword`).
            #
            # You can still declare users the plain NixOS way instead
            # (`users.users.<name>` + `hjem.users.<name>.enable = true`); itera
            # leaves those untouched.
            itera.users.alice = {
              extraGroups = [
                "wheel" # sudo
                "networkmanager"
              ];
              initialPassword = "changeme";

              # Per-user curated-program overrides live right here — each wins
              # per key over the system-wide default (itera.programs.<app>.*):
              #   # Deviate from the system-wide DMS defaults for just this user:
              #   programs.dankMaterialShell.settings.cornerRadius = 8;
              #   # Pick a per-user tiling layout:
              #   programs.mango.layout = "tile";
              #   # Add or override a single mango keybind:
              #   programs.mango.keybinds.terminal = {
              #     modifierKeys = [ "SUPER" ]; keySymbol = "Return";
              #     mangoCommand = "spawn"; commandArguments = "foot";
              #   };
            };
          }
        ];
      };
    };
}
