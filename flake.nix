{
  description = "itera — a batteries-included, opt-out Nix configuration layer built on hjem";

  inputs = {
    # Rolling channel used to build itera itself and as the default for consumers.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Stable channel, kept available so downstream can follow whichever they run.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # $HOME / dotfile management. itera builds its own module layer on top of this.
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning. itera bundles it (see modules/nixos) so a
    # consumer never has to add it as an input themselves.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ephemeral-root persistence. itera only uses its NixOS module.
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # System hardening. itera bundles it (see modules/nixos) so a consumer
    # never has to add it as an input themselves. Powers `itera.hardening`.
    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      # nix-mineral's flake-compat has no itera counterpart, so it stays unfollowed.
    };

    # mango: a dwl-based wlroots Wayland compositor. itera bundles its NixOS
    # module (see modules/nixos) so a consumer never adds it as an input
    # themselves. Powers `itera.desktop.mango`.
    mango = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      # mango's `scenefx` input follows mango's nixpkgs (now ours), so we do not
      # add scenefx ourselves.
    };

    # DankMaterialShell: a Quickshell-based Wayland desktop shell + greeter.
    # itera bundles its NixOS modules (see modules/nixos). Powers
    # `itera.desktop.dankMaterialShell`. Pinned to the `stable` branch upstream
    # recommends for the NixOS modules.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
      # dms's `flake-compat` input has no itera counterpart; it stays unfollowed.
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks.flakeModule

        ./flake/outputs.nix
        ./flake/devshell.nix
        ./flake/checks.nix
      ];
    };
}
