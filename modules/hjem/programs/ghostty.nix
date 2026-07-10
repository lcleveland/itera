# itera's Ghostty user-config battery (home layer).
#
# The system battery `itera.desktop.terminal` installs Ghostty and wires the
# mango `SUPER+t` bind; this hjem battery writes the per-user
# {file}`~/.config/ghostty/config` that Ghostty reads. Because itera's home
# collection is applied to every hjem user, enabling the desktop is enough for
# every user to inherit these defaults — no per-user wiring needed.
#
# Config format: Ghostty's config is a flat `key = value` file (repeated keys are
# allowed, e.g. multiple `keybind` lines), so we type `settings` as
# `attrsOf anything` and render it with `lib.generators.toKeyValue`
# (`listsAsDuplicateKeys` turns a list value into repeated keys). itera's
# opinionated defaults are merged underneath via `mkDefault`, so anything the user
# sets wins — the module stays opt-out.
#
# Deliberately NOT set here:
#   - `font-family`: Ghostty embeds JetBrains Mono Nerd Font as its built-in
#     default and itera ships no fonts module, so we don't reference an
#     uninstalled font.
#   - colors / theme: owned by DankMaterialShell + matugen (wallpaper-derived),
#     so this battery leaves palette keys untouched.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `pkgs` are module args.
# Enable tracks the system toggle by default.
{
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) attrsOf anything;

  cfg = config.itera.programs.ghostty;

  systemEnabled = osConfig.itera.desktop.terminal.enable or false;
in
{
  options.itera.programs.ghostty = {
    enable =
      mkEnableOption "itera's Ghostty user configuration"
      # Follow the system terminal toggle by default: enabling
      # `itera.desktop.terminal` is enough to get the matching home config.
      // {
        default = systemEnabled;
        defaultText = lib.literalExpression "osConfig.itera.desktop.terminal.enable";
      };

    settings = mkOption {
      type = attrsOf anything;
      default = { };
      example = {
        font-size = 13;
        background-opacity = 0.95;
        keybind = [ "ctrl+shift+r=reload_config" ];
      };
      description = ''
        Written to {file}`$XDG_CONFIG_HOME/ghostty/config` as flat `key = value`
        lines. A list value becomes repeated keys (e.g. `keybind`). itera's
        opinionated defaults are merged underneath via `mkDefault`, so anything
        set here wins.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Warn (don't fail) if the home config is on but the system terminal is off —
    # the config would be written for a Ghostty that isn't installed.
    warnings = lib.optional (!systemEnabled) ''
      itera.programs.ghostty is enabled for a user but
      itera.desktop.terminal.enable is false — the Ghostty config will be written
      to $HOME without the terminal being installed.
    '';

    # Opinionated "batteries-included" defaults; explicit user values override.
    itera.programs.ghostty.settings = {
      font-size = mkDefault 12;
      window-padding-x = mkDefault 8;
      window-padding-y = mkDefault 8;
      cursor-style = mkDefault "block";
    };

    xdg.config.files."ghostty/config" = mkIf (cfg.settings != { }) {
      text = lib.generators.toKeyValue {
        mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
        listsAsDuplicateKeys = true;
      } cfg.settings;
    };
  };
}
