# itera shell battery — fzf fuzzy finder (+ fzf-tab).
#
# Installs fzf and wires its interactive integration into zsh: `Ctrl+R` history
# search, `Ctrl+T` file picker, `Alt+C` cd, and fuzzy path completion. Defaults use
# fd for the file list and bat for previews (both shipped by sibling modules).
#
# Beyond eiros, this also ships fzf-tab: it replaces zsh's default completion menu
# with an fzf-driven fuzzy selector (with previews). fzf-tab must be sourced AFTER
# `compinit` (Oh My Zsh runs it early during `interactiveShellInit`) and BEFORE
# zsh-syntax-highlighting (NixOS appends that last, outside interactiveShellInit),
# so sourcing it here lands in the correct position.
#
# Opt-OUT (default ON), gated on the zsh battery for its shell hooks.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool str;

  cfg = config.itera.shell.fzf;
  zshEnabled = config.itera.shell.zsh.enable;
in
{
  options.itera.shell.fzf = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Install fzf for interactive fuzzy finding (Ctrl+R history, Ctrl+T file picker).";
    };

    defaultCommand = mkOption {
      type = str;
      default = "fd --type f --hidden --follow --exclude .git";
      description = "Command used by fzf to generate the file list (FZF_DEFAULT_COMMAND).";
    };

    defaultOpts = mkOption {
      type = str;
      default = "--preview 'bat --color=always --style=numbers {}'";
      description = "Default fzf options passed to every invocation (FZF_DEFAULT_OPTS).";
    };

    fzfTab.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Load the fzf-tab plugin so zsh tab-completion menus become fzf-driven
        fuzzy selectors with previews. Requires the zsh battery.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = [ pkgs.fzf ];

    environment.variables = {
      FZF_DEFAULT_COMMAND = cfg.defaultCommand;
      FZF_DEFAULT_OPTS = cfg.defaultOpts;
    };

    programs.zsh.interactiveShellInit = mkIf zshEnabled (
      ''
        source ${pkgs.fzf}/share/fzf/completion.zsh
        source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      ''
      + lib.optionalString cfg.fzfTab.enable ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        # Let fzf-tab own the completion menu instead of zsh's default selector.
        zstyle ':completion:*' menu no
        # Preview directory contents when completing `cd`.
        zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath 2>/dev/null || ls -1 $realpath'
      ''
    );
  };
}
