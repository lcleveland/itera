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

            # Turn on itera's opinionated system defaults (all opt-out).
            itera.enable = true;

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
