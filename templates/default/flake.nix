{
  description = "A NixOS configuration built on itera + hjem";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # hjem manages your $HOME. itera's home modules are class-`hjem` submodules,
    # so itera MUST share this exact hjem (see `follows` below) — otherwise
    # evaluation breaks with confusing submodule-class errors.
    hjem.url = "github:feel-co/hjem";

    itera = {
      url = "github:lcleveland/itera";
      inputs.nixpkgs.follows = "nixpkgs"; # build itera against your channel
      inputs.hjem.follows = "hjem"; # CRITICAL: share one hjem
    };
  };

  outputs =
    { nixpkgs, itera, ... }:
    {
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

              # Hardware layer — replaces a generated hardware-configuration.nix.
              # The initrd kernel-module default boots virtually any modern UEFI
              # x86 machine; you normally only pick a CPU vendor.
              hardware.cpu = "auto"; # or "intel" / "amd"
              #   hardware.initrd.availableKernelModules = [ ... ]; # exotic controller

              # Declarative disk layout + ephemeral (tmpfs) root, bundled with
              # itera (no extra inputs). Both are ON by default. disko WIPES the
              # target device and has no safe default, so you MUST point it at a
              # disk — the build fails with an assertion until you do. This is the
              # one genuinely per-machine value.
              disko.device = "/dev/nvme0n1"; # CHANGE ME — disko WIPES this disk
              #   disko.swapSize = "8G";       # optional swap partition
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
              #   hardware.facter.reportPath = ./facter.json; # nix run nixpkgs#nixos-facter -- -o facter.json
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
            };

            # Per-user home overrides plug in under the hjem namespace, e.g.:
            #   hjem.users.alice.itera.programs.helix.enable = true;
            #   # Deviate from the system-wide DMS defaults for just this user:
            #   hjem.users.alice.itera.programs.dankMaterialShell.settings.cornerRadius = 8;
            #   # Add or override a single mango keybind:
            #   hjem.users.alice.itera.programs.mango.keybinds.terminal = {
            #     modifierKeys = [ "SUPER" ]; keySymbol = "Return";
            #     mangoCommand = "spawn"; commandArguments = "foot";
            #   };
          }
        ];
      };
    };
}
