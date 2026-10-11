{
  description = "itera — a batteries-included, opt-out Nix configuration layer built on hjem";

  inputs = {
    # Rolling channel used to build itera itself and as the default for consumers.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Stable channel, kept available so downstream can follow whichever they run.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

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
      # Only used by impermanence's own tests.
      inputs.home-manager.follows = "";
    };

    # System hardening. itera bundles it (see modules/nixos) so a consumer
    # never has to add it as an input themselves. Powers `itera.hardening`.
    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        # flake-compat only serves non-flake users; never fetch it.
        flake-compat.follows = "";
      };
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

    # DankMaterialShell: a Quickshell-based Wayland desktop shell. itera bundles
    # its NixOS module (see modules/nixos). Powers the shell half of
    # `itera.desktop.dankMaterialShell`. Tracks `master`, not the `stable`
    # branch: mango 0.18 renamed every config key with no aliases, and only
    # master writes the snake_case keys into the mango/dms/*.conf fragments that
    # itera's mango config sources. Move back to `stable` once a release has it
    # (`dms config mango-migrate` exists there). The greeter used to live here
    # too but was extracted upstream into its own repo — see `dank-greeter` below.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "";
    };

    # DMS greeter: extracted from DankMaterialShell into its own repo upstream.
    # itera bundles its NixOS module (see modules/nixos). Powers the greeter half
    # of `itera.desktop.dankMaterialShell` via `programs.dms-greeter`. Tracks
    # `master` — dank-greeter has no `stable` branch (unlike dms).
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
      # dank-greeter's `dank-qml-common` is a source-only (flake = false) input
      # with no itera counterpart; it stays unfollowed.
    };

    # DMS IP Indicator plugin: a dank-bar widget (public IP / ISP / location)
    # shipped as a default-on plugin of `itera.desktop.dankMaterialShell`.
    # Source-only (`flake = false`) — it's just QML, so there is no nixpkgs input
    # to follow; the revision lives in `flake.lock` and `nix flake update
    # dms-ipindicator` bumps it (no manual hash).
    dms-ipindicator = {
      url = "github:hthienloc/dms-ipIndicator";
      flake = false;
    };

    # treefmt-nix and git-hooks are dev-only: they live in ./dev/flake.nix and
    # load into the `dev` partition, so they stay out of consumers' lock files.

    # Secure Boot & measured boot for UEFI. itera bundles its NixOS module (see
    # modules/nixos) so a consumer never adds it as an input themselves. Powers
    # `itera.secureBoot`.
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
      # Only used for lanzaboote's own checks.
      inputs.pre-commit.follows = "";
      # Its rust toolchain inputs (crane, rust-overlay) build the tool itself, so
      # they stay. It has no flake-parts input.
    };

    # Declarative age-encrypted secrets. itera bundles its NixOS module (see
    # modules/nixos). Powers `itera.secrets`.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      # agenix's darwin/home-manager inputs feed modules itera never imports, so
      # they stay unfollowed.
    };

    # Declarative sops-encrypted secrets — the other half of itera's secrets
    # story. Where agenix keeps one `.age` file per secret, sops-nix keeps many
    # secrets in one encrypted YAML/JSON file, which is what team/multi-host
    # setups usually want. itera bundles its NixOS module (see modules/nixos).
    # Powers `itera.sops`.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Weekly-updated nix-index database + comma. itera bundles its NixOS module
    # (see modules/nixos). Powers `itera.nixIndex`.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Flatpak management. itera bundles its NixOS module (see
    # modules/nixos). Powers `itera.desktop.flatpak`. It has no nixpkgs input to
    # follow.
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # Per-machine hardware quirk profiles. NOT bundled/auto-imported — profiles
    # are import-time selections the module system can't toggle from config — so
    # it is re-exported via flake/outputs.nix instead, letting a consumer add
    # their board's profile without adding this as their own input.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
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
        flake-parts.flakeModules.partitions
        ./flake/outputs.nix
        ./flake/cli.nix
        ./flake/vm.nix
        ./flake/test-host.nix
      ];

      # Dev tooling (formatter, git hooks, dev shell, checks) evaluates in its
      # own partition with ./dev's inputs, so consumers never lock them.
      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
      };
      partitions.dev = {
        extraInputsFlake = ./dev;
        module =
          { inputs, ... }:
          {
            imports = [
              inputs.treefmt-nix.flakeModule
              inputs.git-hooks.flakeModule
              ./flake/devshell.nix
              ./flake/checks.nix
            ];
          };
      };
    };
}
