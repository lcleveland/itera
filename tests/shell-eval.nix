# Evaluation check for itera's shell battery: zsh (Oh My Zsh + spaceship,
# autosuggestions, syntax highlighting, shared history, default login shell) and
# its companion tools (fzf + fzf-tab, zoxide, atuin, direnv, pay-respects, zellij,
# and the CLI-replacement aliases eza/bat/ripgrep/fd/procs/duf/gping/lazygit).
#
# Like the other *-eval checks, we evaluate two NixOS configurations — one at
# defaults, one with zsh turned off — and assert the generated config. `nix build`
# forces evaluation and fails loudly on any false assertion.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  mkEval =
    extra:
    (nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.default
        {
          system.stateVersion = "25.05";
          itera = {
            enable = true;
            disko = {
              enable = true;
              device = "/dev/vda";
            };
            impermanence.enable = true;
          };
        }
        extra
      ];
    }).config;

  # Defaults: the whole shell battery on (except zellij, which is opt-in).
  base = mkEval { };

  # zsh turned off: the login shell and every companion shell hook must drop.
  zshOff = mkEval { itera.shell.zsh.enable = false; };

  hasPkg =
    pname: pkgList:
    builtins.any (p: (p.pname or p.name or "") == pname || lib.hasInfix pname (p.name or "")) pkgList;

  checks = {
    # --- core zsh (default on) ---
    "zsh is enabled" = base.programs.zsh.enable;
    "zsh is the default login shell" = (base.users.defaultUserShell.pname or "") == "zsh";
    "autosuggestions are on" = base.programs.zsh.autosuggestions.enable;
    "syntax highlighting is on" = base.programs.zsh.syntaxHighlighting.enable;
    "history size is 50000" = base.programs.zsh.histSize == 50000;
    "SHARE_HISTORY is set" = builtins.elem "SHARE_HISTORY" base.programs.zsh.setOptions;

    # --- Oh My Zsh + spaceship (default on) ---
    "oh-my-zsh is enabled" = base.programs.zsh.ohMyZsh.enable;
    "spaceship is the theme" = base.programs.zsh.ohMyZsh.theme == "spaceship";
    "spaceship-prompt is a custom pkg" = hasPkg "spaceship-prompt" base.programs.zsh.ohMyZsh.customPkgs;
    "git plugin is enabled" = builtins.elem "git" base.programs.zsh.ohMyZsh.plugins;

    # --- integrations hook into zsh init (default on) ---
    "fzf key-bindings are sourced" =
      lib.hasInfix "key-bindings.zsh" base.programs.zsh.interactiveShellInit;
    "fzf-tab plugin is sourced" = lib.hasInfix "fzf-tab" base.programs.zsh.interactiveShellInit;
    "zoxide init is sourced" = lib.hasInfix "zoxide init zsh" base.programs.zsh.interactiveShellInit;
    "atuin init is sourced" = lib.hasInfix "atuin init zsh" base.programs.zsh.interactiveShellInit;
    "pay-respects init is sourced" =
      lib.hasInfix "pay-respects zsh" base.programs.zsh.interactiveShellInit;

    # --- direnv + nix-direnv (default on), zsh hook gated on the zsh battery ---
    "direnv is enabled" = base.programs.direnv.enable;
    "nix-direnv is enabled" = base.programs.direnv.nix-direnv.enable;
    "direnv zsh integration is on" = base.programs.direnv.enableZshIntegration;
    "direnv hook is sourced" = lib.hasInfix "hook zsh" base.programs.zsh.interactiveShellInit;
    "keep-outputs retained for nix-direnv" = base.nix.settings.keep-outputs == true;
    "keep-derivations retained for nix-direnv" = base.nix.settings.keep-derivations == true;

    # --- CLI-replacement aliases (default on) ---
    "ls -> eza" = base.programs.zsh.shellAliases.ls == "eza --icons";
    "cat -> bat" = base.programs.zsh.shellAliases.cat == "bat";
    "grep -> rg" = base.programs.zsh.shellAliases.grep == "rg";
    "find -> fd" = base.programs.zsh.shellAliases.find == "fd";
    "lg -> lazygit" = base.programs.zsh.shellAliases.lg == "lazygit";

    # --- zellij is opt-in (default off) ---
    "zellij is off by default" = !(hasPkg "zellij" base.environment.systemPackages);

    # --- zsh disabled: shell drops, companion hooks/aliases fall away ---
    "zsh off -> programs.zsh disabled" = !zshOff.programs.zsh.enable;
    "zsh off -> login shell is not zsh" = (zshOff.users.defaultUserShell.pname or "") != "zsh";
    "zsh off -> no shell aliases" = !(zshOff.programs.zsh.shellAliases ? ls);
    "zsh off -> no init hooks" = !(lib.hasInfix "zoxide init" zshOff.programs.zsh.interactiveShellInit);
    "zsh off -> direnv zsh hook drops" = !zshOff.programs.direnv.enableZshIntegration;
  };

  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
pkgs.runCommand "itera-shell-eval" { } (
  if failed == [ ] then
    "touch $out"
  else
    throw "itera shell eval check failed: ${lib.concatStringsSep "; " failed}"
)
