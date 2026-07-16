{ inputs, ... }:
{
  # `formatting` (treefmt) and `pre-commit` (git-hooks) checks are contributed by
  # their flakeModules. Here we add itera's module regression tests. `nix flake
  # check` is the single entry point that runs all three.
  perSystem =
    { pkgs, lib, ... }:
    {
      checks =
        # Auto-discovered VM tests under tests/nixos.
        (import ../tests {
          inherit pkgs lib;
          inherit (inputs) self;
          # VM boot tests need KVM; hosted aarch64 runners have none, so only
          # discover them on x86_64. The eval check below still runs everywhere.
          testDirectory = if pkgs.stdenv.hostPlatform.isx86_64 then ../tests/nixos else ../tests/nonexistent;
        })
        # Evaluation check for the disko + impermanence batteries.
        // {
          disko-impermanence-eval = import ../tests/eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };

          # Evaluation check for the desktop batteries (mango + DankMaterialShell).
          desktop-eval = import ../tests/desktop-eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };

          # Evaluation check for the default-settings-for-all-users system
          # (itera.users + DMS settings + mango keybinds).
          user-defaults-eval = import ../tests/user-defaults-eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };

          # Evaluation check for the ecosystem-integration batteries (agenix,
          # nix-index, virtualisation, Nemo, Secure Boot, Flatpak, facter).
          integrations-eval = import ../tests/integrations-eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };

          # Evaluation check for the shell battery (nushell default login shell +
          # carapace completion + the per-user nushell home config).
          nushell-eval = import ../tests/nushell-eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };

          # Evaluation check for the nh battery (nh as rebuild front-end + nh
          # clean owning scheduled GC, with the gc.nix hand-off).
          nh-eval = import ../tests/nh-eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };

          # Evaluation check for the cli battery (the consumer `itera` command).
          cli-eval = import ../tests/cli-eval.nix {
            inherit pkgs lib;
            inherit (inputs) self nixpkgs;
          };
        };
    };
}
