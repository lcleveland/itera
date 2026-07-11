# itera shell battery — direnv, per-directory environment activation.
#
# Installs direnv and enables nix-direnv, the fast/GC-safe implementation of
# `use flake` / `use nix` that caches `nix develop` shells so an `.envrc` reload
# doesn't re-evaluate the flake every time. Ported from itera's predecessor
# (eiros' `system/nix/direnv.nix` + the keep-outputs/keep-derivations retention
# from `system/nix/build.nix`).
#
# This is a thin wrapper over nixpkgs' first-class `programs.direnv` module, which
# installs the package, writes /etc/direnv/direnvrc (sourcing nix-direnv and any
# user ~/.config/direnv/direnvrc), and injects the shell hook. Complements the
# `"direnv"` Oh My Zsh plugin already carried by the zsh battery, which supplies
# the prompt-side integration.
#
# Opt-OUT (default ON); zsh hook gated on the zsh battery.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.shell.direnv;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.direnv = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install direnv for automatic per-directory environment activation from .envrc files.";
    };

    nixDirenv.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable nix-direnv: caches {command}`nix develop` / `use flake` shells so
        direnv reloads are fast and survive garbage collection.
      '';
    };

    silent.enable = mkOption {
      type = bool;
      default = false;
      description = "Hide direnv's per-directory load/unload logging.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = cfg.nixDirenv.enable;
      silent = cfg.silent.enable;
      # Gate the zsh hook on itera's zsh battery; bash/fish integration stays at
      # the module's defaults (inert unless those shells are actually used).
      enableZshIntegration = zshEnabled;
    };

    # nix-direnv's cached dev shells only survive `nix-collect-garbage` when the
    # build outputs and derivations are retained. The programs.direnv module does
    # not set these; eiros carried them in system/nix/build.nix.
    nix.settings = mkIf cfg.nixDirenv.enable {
      keep-outputs = mkDefault true;
      keep-derivations = mkDefault true;
    };
  };
}
