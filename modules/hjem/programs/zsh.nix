# itera's zsh user-config battery (home layer).
#
# The system battery `itera.shell.zsh` (modules/nixos/core/shell/zsh.nix) makes
# zsh the login shell and generates the global /etc/zshrc with all the real
# interactive config (Oh My Zsh, spaceship, aliases, tool hooks). This hjem
# battery writes the per-user {file}`~/.zshrc` that must EXIST alongside it.
#
# Why a (near-empty) ~/.zshrc is required: with no zsh startup file in $HOME,
# zsh runs `zsh-newuser-install` on every interactive login — it clears the
# screen (blank blinking caret), blocks waiting for a keypress, and eats the
# first characters typed. The NixOS-generated /etc/zshrc does NOT suppress this;
# only the presence of a user startup file does (the wizard itself advises
# `touch ~/.zshrc`). itera has no home-manager to auto-generate one, and the
# wipe-every-boot impermanent home never persists a hand-created one, so the
# wizard would return on every boot without this module.
#
# hjem writes the file as a /nix/store symlink (clobber defaults true), so it is
# recreated on every activation and survives the impermanent home with no
# persistence wiring. All real config lives in /etc/zshrc, which zsh sources
# BEFORE ~/.zshrc, so this comment-only file changes nothing else.
#
# Runs inside the hjem user submodule (see modules/hjem/default.nix): the `files`
# sink is unprefixed and `osConfig` is a module arg. Enable tracks the system
# zsh toggle by default.
{
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.itera.programs.zsh;

  systemEnabled = osConfig.itera.shell.zsh.enable or false;
in
{
  options.itera.programs.zsh = {
    enable =
      mkEnableOption "itera's per-user zsh home configuration"
      # Follow the system zsh toggle by default: enabling `itera.shell.zsh` is
      # enough to get the matching ~/.zshrc.
      // {
        default = systemEnabled;
        defaultText = lib.literalExpression "osConfig.itera.shell.zsh.enable";
      };
  };

  config = mkIf cfg.enable {
    # A user ~/.zshrc must exist or zsh runs zsh-newuser-install on every
    # interactive login (see the header comment). Real config lives in the
    # NixOS-generated /etc/zshrc, sourced before this file — this only needs to
    # exist to suppress the wizard.
    files.".zshrc".text = ''
      # Managed by itera (modules/hjem/programs/zsh.nix). Intentionally minimal.
      # Interactive zsh config lives in the NixOS-generated /etc/zshrc, which zsh
      # sources before this file. This file exists to suppress zsh-newuser-install.
    '';
  };
}
