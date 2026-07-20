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

    # When the GitHub CLI ships in this battery, wire it up as git's credential
    # helper over HTTPS so a `gh auth login` transparently authenticates git too
    # (clone/push/pull) — no separate PAT or credential store to manage.
    programs.git = mkIf (lib.elem pkgs.gh cfg.packages) {
      enable = true;
      config.credential = {
        "https://github.com".helper = "!${lib.getExe pkgs.gh} auth git-credential";
        "https://gist.github.com".helper = "!${lib.getExe pkgs.gh} auth git-credential";
      };
    };
  };
}
