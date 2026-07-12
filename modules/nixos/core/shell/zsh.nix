# itera's shell battery — core zsh module.
#
# itera shipped no shell config until now, falling back to NixOS's implicit bash.
# This battery makes zsh the default login shell with the same opinionated setup
# itera's predecessor (eiros) carried: Oh My Zsh + the spaceship prompt,
# autosuggestions, syntax highlighting, and a large shared history.
#
# zsh is a SYSTEM concern in NixOS: `programs.zsh.enable` is what makes zsh a valid
# login shell, and ohMyZsh / autosuggestions / syntaxHighlighting / history /
# shellAliases / interactiveShellInit all live under `programs.zsh.*`. All the real
# interactive config is generated into the global /etc/zshrc from here.
#
# There IS a hjem home half though: `modules/hjem/programs/zsh.nix` writes a
# near-empty per-user ~/.zshrc. It must exist or zsh runs zsh-newuser-install on
# every interactive login (blank screen, eats the first keystrokes) — the global
# /etc/zshrc does not suppress that, only a user startup file does. See that
# module for the full rationale.
#
# The companion tools in this directory (fzf, zoxide, atuin, pay-respects, and the
# CLI-replacement aliases) all inject into zsh and guard their hooks on
# `itera.shell.zsh.enable`, so turning zsh off cleanly disables their integration.
#
# Opt-OUT (default ON): set `itera.shell.zsh.enable = false` to drop it. Keep zsh
# but restore bash as the login shell with `itera.shell.zsh.defaultShell.enable = false`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    bool
    int
    str
    listOf
    package
    ;

  cfg = config.itera.shell.zsh;
in
{
  options.itera.shell.zsh = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install and configure zsh system-wide (Oh My Zsh + spaceship prompt,
        autosuggestions, syntax highlighting, shared history). On by default
        whenever {option}`itera.enable` is set; set to `false` to opt out.
      '';
    };

    defaultShell.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Set zsh as the default login shell for all users
        ({option}`users.defaultUserShell`). Disable to keep zsh installed and
        configured while leaving the login shell as bash.
      '';
    };

    autosuggestions.enable = mkOption {
      type = bool;
      default = true;
      description = "Enable zsh-autosuggestions (suggests commands from history as you type).";
    };

    syntaxHighlighting.enable = mkOption {
      type = bool;
      default = true;
      description = "Enable zsh-syntax-highlighting (highlights commands as you type).";
    };

    histSize = mkOption {
      type = int;
      default = 50000;
      description = "Maximum number of history entries to keep.";
    };

    setOptions = mkOption {
      type = listOf str;
      default = [
        "HIST_IGNORE_DUPS"
        "HIST_IGNORE_SPACE"
        "SHARE_HISTORY"
      ];
      description = "zsh options to enable (setopt).";
    };

    ohMyZsh = {
      enable = mkEnableOption "the Oh My Zsh framework" // {
        default = true;
      };

      theme = mkOption {
        type = str;
        default = "spaceship";
        example = "robbyrussell";
        description = "Oh My Zsh theme to use.";
      };

      plugins = mkOption {
        type = listOf str;
        default = [
          "colored-man-pages"
          "copypath"
          "direnv"
          "extract"
          "git"
          "history"
          "sudo"
        ];
        description = "Oh My Zsh plugins to enable.";
      };

      customPackages = mkOption {
        type = listOf package;
        default = [ pkgs.spaceship-prompt ];
        defaultText = lib.literalExpression "[ pkgs.spaceship-prompt ]";
        description = "Additional packages providing Oh My Zsh themes or plugins (wired to `programs.zsh.ohMyZsh.customPkgs`).";
      };

      spaceshipPromptOrder = mkOption {
        type = listOf str;
        default = [
          "user"
          "dir"
          "host"
          "git"
          "nix_shell"
          "exec_time"
          "line_sep"
          "jobs"
          "exit_code"
          "char"
        ];
        description = ''
          Prompt sections for the spaceship theme (`SPACESHIP_PROMPT_ORDER`).
          spaceship precompiles every section in the order at shell startup, and
          its built-in order lists dozens of language/tool sections (node, ruby,
          php, golang, docker, aws, kubectl, terraform, …) that most shells never
          use — measured at ~200ms of the interactive startup. This lean default
          keeps startup roughly twice as fast while still showing the common
          context (each section only renders when relevant). Set to `[ ]` to leave
          spaceship's built-in order untouched. Only applies with the spaceship
          theme.
        '';
      };
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    # Normal priority (not mkDefault): NixOS's bash module already sets this at
    # mkDefault, so a tie would conflict. Normal priority wins over that; consumers
    # who want a different login shell use `defaultShell.enable = false` or mkForce.
    users.defaultUserShell = mkIf cfg.defaultShell.enable pkgs.zsh;

    # Oh My Zsh runs compinit itself; skip NixOS's global compinit to avoid
    # paying for two full compinit passes on every interactive startup. With OMZ
    # off, leave the global compinit on so completions still initialize.
    programs.zsh.enableGlobalCompInit = mkDefault (!cfg.ohMyZsh.enable);

    # Trim spaceship's prompt sections. NixOS's interactiveShellInit lands in
    # /etc/zshrc before oh-my-zsh sources the theme, so setting the array here is
    # picked up when spaceship loads. Skipped when the list is empty or the theme
    # isn't spaceship. See `spaceshipPromptOrder` for the perf rationale.
    programs.zsh.interactiveShellInit = mkIf (
      cfg.ohMyZsh.enable && cfg.ohMyZsh.theme == "spaceship" && cfg.ohMyZsh.spaceshipPromptOrder != [ ]
    ) "SPACESHIP_PROMPT_ORDER=(${lib.concatStringsSep " " cfg.ohMyZsh.spaceshipPromptOrder})\n";

    programs.zsh = {
      enable = true;

      autosuggestions.enable = mkDefault cfg.autosuggestions.enable;
      syntaxHighlighting.enable = mkDefault cfg.syntaxHighlighting.enable;

      histSize = mkDefault cfg.histSize;
      inherit (cfg) setOptions;

      ohMyZsh = mkIf cfg.ohMyZsh.enable {
        enable = true;
        theme = mkDefault cfg.ohMyZsh.theme;
        plugins = cfg.ohMyZsh.plugins;
        customPkgs = cfg.ohMyZsh.customPackages;
      };
    };
  };
}
