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

            # Turn on itera's opinionated system defaults (all opt-out). This
            # alone gives you a bootable system: systemd-boot on the ESP, the
            # systemd initrd, flakes enabled, a pinned stateVersion, a locale, and
            # NetworkManager. Every value is a mkDefault, so override any of them.
            itera = {
              enable = true;

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
              # itera — no extra inputs needed. Uncomment to use; disko WIPES the
              # target device, so replace ./hardware-configuration.nix's
              # fileSystems accordingly.
              #   disko = {
              #     enable = true;
              #     device = "/dev/nvme0n1";
              #   };
              #   impermanence = {
              #     enable = true; # method defaults to "tmpfs"
              #     directories = [ "/var/lib/tailscale" ];
              #   };
            };

            # A login user. itera does not manage users yet, so declare them the
            # normal NixOS way. CHANGE ME before deploying: pick your username and
            # set a real password (prefer `hashedPassword` / `hashedPasswordFile`
            # over `initialPassword`).
            users.users.alice = {
              isNormalUser = true;
              extraGroups = [
                "wheel" # sudo
                "networkmanager"
              ];
              initialPassword = "changeme";
            };

            # Per-user home configuration under itera's namespace.
            hjem.users.alice = {
              enable = true;
              # Curated program modules ("batteries") plug in here, e.g.:
              #   itera.programs.helix.enable = true;
              #   itera.profiles.desktop.enable = true;
            };
          }
        ];
      };
    };
}
