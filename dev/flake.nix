{
  description = "itera development-only inputs (formatter, git hooks)";

  # Loaded into the root flake's `dev` partition (see ../flake.nix), so these
  # inputs never land in a consumer's flake.lock. This flake only provides
  # inputs; its outputs are unused.
  inputs = {
    # Their own nixpkgs is only used for their self-tests; the flakeModules use
    # the root flake's perSystem `pkgs`.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "";
      inputs.flake-compat.follows = "";
    };
  };

  outputs = _: { };
}
