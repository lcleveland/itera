_: {
  perSystem =
    { config, pkgs, ... }:
    {
      # treefmt-nix flakeModule: sets `formatter.<system>` and `checks.formatting`.
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true; # nixfmt-rfc-style (RFC 166), nixpkgs-aligned
          statix.enable = true; # anti-pattern linter
          deadnix.enable = true; # dead-code detection
          prettier.enable = true; # markdown / yaml / json
        };
      };

      # git-hooks.nix flakeModule: sets `checks.pre-commit` + `installationScript`.
      pre-commit.settings.hooks = {
        treefmt.enable = true;
        statix.enable = true;
        deadnix.enable = true;
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.treefmt.build.devShell ];
        shellHook = config.pre-commit.installationScript;
        packages = with pkgs; [
          nil
          nixd
          nixfmt-rfc-style
          statix
          deadnix
          nix-output-monitor
        ];
      };

      # itera's own packages (empty until custom packages land).
      packages = import ../pkgs { inherit pkgs; };
    };
}
