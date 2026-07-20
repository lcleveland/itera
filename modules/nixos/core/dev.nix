# itera's developer-tooling battery.
#
# A freshly installed itera system ships nothing to work on a Nix configuration
# with — notably no `git`, so you can't clone, edit, and commit your own flake
# (or itera itself) out of the box. Every other package itera installs is scoped
# to the battery that needs it; the dev-shell tools (nil, nixfmt, …) live only in
# `nix develop` and never land on an installed host. This battery closes that gap
# with a small, curated set of system-wide tooling.
#
# Deliberately lean: the default is `git` (the one thing you cannot bootstrap a
# config workflow without) plus the GitHub CLI `gh` (open/manage PRs against your
# flake without leaving the shell). `packages` is the extension point — append
# your own editors/CLIs, or drop the battery entirely and install per-user via
# `itera.users.<name>.packages`.
#
# Opt-OUT (default ON with `itera.enable`), following the core-battery shape.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool listOf package;

  cfg = config.itera.dev;

  # gh ships as git's credential helper only when the CLI is actually in the
  # battery — drop it from `packages` and the wiring drops with it, rather than
  # pointing git at a binary that isn't installed.
  ghCredentialHelper = lib.elem pkgs.gh cfg.packages;

  # The hardening layer (nix-mineral, via `itera.hardening`) also writes
  # /etc/gitconfig — its Kicksecure git hardening (no symlinks, fsck on fetch).
  # Only one module can own that file, so when nix-mineral is active we take it
  # over: disable nix-mineral's entry below and fold its hardening back into our
  # own `programs.git.config` (see the `mkIf hardeningActive` block), instead of
  # colliding on `environment.etc.gitconfig`.
  hardeningActive = config.nix-mineral.enable or false;
in
{
  options.itera.dev = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install a small curated set of developer tooling system-wide (by default
        {command}`git` and the GitHub CLI {command}`gh`), so a freshly installed
        host can work on a Nix configuration. On by default whenever
        {option}`itera.enable` is set; set to `false` to omit it.
      '';
    };

    packages = mkOption {
      type = listOf package;
      default = [
        pkgs.git
        pkgs.gh
      ];
      defaultText = lib.literalExpression "[ pkgs.git pkgs.gh ]";
      example = lib.literalExpression "[ pkgs.git pkgs.gh pkgs.gnumake pkgs.jq ]";
      description = ''
        System-wide developer tooling installed when {option}`itera.dev.enable`
        is set. Defaults to {command}`git` and the GitHub CLI {command}`gh`; append
        your own tools here, or install per-user via
        {option}`itera.users.<name>.packages` instead.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = cfg.packages;

    # Wire gh up as git's HTTPS credential helper so a `gh auth login`
    # transparently authenticates git too (clone/push/pull) — no separate PAT or
    # credential store to manage.
    programs.git = mkIf ghCredentialHelper {
      enable = true;
      config = lib.mkMerge [
        {
          credential = {
            "https://github.com".helper = "!${lib.getExe pkgs.gh} auth git-credential";
            "https://gist.github.com".helper = "!${lib.getExe pkgs.gh} auth git-credential";
          };
        }
        # Preserve nix-mineral's Kicksecure git hardening now that we own the file
        # (mirrors github.com/Kicksecure/security-misc's etc/gitconfig).
        (mkIf hardeningActive {
          core.symlinks = false;
          transfer.fsckobjects = true;
          fetch.fsckobjects = true;
          receive.fsckobjects = true;
        })
      ];
    };

    # Hand /etc/gitconfig to us (above) rather than nix-mineral, so the two don't
    # both define it. Overridable — a host that flips this back on owns the
    # collision and should drop our helper via `itera.dev.packages`.
    nix-mineral = mkIf (ghCredentialHelper && hardeningActive) {
      settings.etc.kicksecure-gitconfig = lib.mkDefault false;
    };
  };
}
