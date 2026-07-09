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
          ./hardware-configuration.nix

          # A single import: pulls in hjem and wires itera's home layer for you.
          itera.nixosModules.default

          {
            nixpkgs.overlays = [ itera.overlays.default ];

            # itera's opinionated system defaults are opt-out — on by default, so
            # this import alone gives you a bootable system: systemd-boot on the
            # ESP, the systemd initrd, flakes enabled, a pinned stateVersion, a
            # locale, NetworkManager, hardening, and the desktop. Every value is a
            # mkDefault, so override any of them. Set `itera.enable = false` to
            # turn the whole layer off.
            itera = {
              # Override individual core-boot defaults as needed:
              networking.hostName = "myhost";
              #   locale.timeZone = "Europe/London";
              #   locale.defaultLocale = "en_GB.UTF-8";
              #   boot.kernelPackages = pkgs.linuxPackages_latest;

              # Pin the NixOS release your stateful data matches. Set this ONCE
              # at install time to the release you installed from, then never
              # change it.
              nix.stateVersion = "25.05";

              # Declarative disk layout + ephemeral (tmpfs) root. Bundled with
              # itera — no extra inputs needed. These are opt-out (ON by default),
              # but disko WIPES the target device and has no safe default device,
              # so this template disables them and relies on the generated
              # ./hardware-configuration.nix instead. To use them: set
              # `disko.enable = true` with a `device`, DELETE the fileSystems block
              # in ./hardware-configuration.nix, and enable impermanence.
              disko.enable = false;
              impermanence.enable = false;
              #   disko = {
              #     enable = true;
              #     device = "/dev/nvme0n1";
              #   };
              #   impermanence = {
              #     enable = true; # method defaults to "tmpfs"
              #     directories = [ "/var/lib/tailscale" ];
              #   };
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
