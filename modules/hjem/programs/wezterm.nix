# itera's WezTerm user-config battery (home layer).
#
# The system battery `itera.desktop.terminal` installs WezTerm (+ JetBrains Mono
# Nerd Font) and wires the mango `SUPER+t` bind; this hjem battery writes the
# per-user {file}`~/.config/wezterm/wezterm.lua` that WezTerm reads. Because
# itera's home collection is applied to every hjem user, enabling the desktop is
# enough for every user to inherit these defaults — no per-user wiring needed.
#
# Config format: WezTerm's config is Lua — a script that builds and returns a
# config table. We keep the declarative surface simple: `settings` is an
# `attrsOf anything` rendered as `config.<key> = <lua-value>` via a small local
# `toLua` serializer (scalars, lists, and shallow tables), and itera's opinionated
# defaults are merged underneath via `mkDefault` so anything the user sets wins.
# `fontFamily` is special-cased because the font is a `wezterm.font(...)` call, not
# a plain scalar, and `extraLua` is an escape hatch for arbitrary Lua.
#
# Deliberately NOT set here:
#   - colors / theme: WezTerm ships good built-in defaults; itera leaves the
#     palette untouched. (Ghostty's colors used to be wallpaper-derived via
#     DankMaterialShell + matugen; WezTerm is not wired into that.)
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
  inherit (lib.types)
    attrsOf
    anything
    str
    nullOr
    lines
    ;

  cfg = config.itera.programs.wezterm;

  systemEnabled = osConfig.itera.desktop.terminal.enable or false;

  # Render a Nix value as a Lua literal. Handles the scalar/list/shallow-table
  # shapes WezTerm config keys use; anything else is a config error.
  toLua =
    v:
    if builtins.isString v then
      "'${lib.escape [ "'" "\\" ] v}'"
    else if builtins.isBool v then
      (if v then "true" else "false")
    else if builtins.isInt v || builtins.isFloat v then
      toString v
    else if builtins.isList v then
      "{ ${lib.concatMapStringsSep ", " toLua v} }"
    else if builtins.isAttrs v then
      "{ ${lib.concatStringsSep ", " (lib.mapAttrsToList (k: val: "${k} = ${toLua val}") v)} }"
    else
      throw "itera.programs.wezterm.settings: unsupported Lua value type for `${builtins.typeOf v}`";

  settingsLua = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "config.${k} = ${toLua v}") cfg.settings
  );

  fontLua = lib.optionalString (
    cfg.fontFamily != null
  ) "config.font = wezterm.font('${cfg.fontFamily}')";

  configText = ''
    local wezterm = require 'wezterm'
    local config = wezterm.config_builder()

    ${settingsLua}
    ${fontLua}
    ${cfg.extraLua}

    return config
  '';
in
{
  options.itera.programs.wezterm = {
    enable =
      mkEnableOption "itera's WezTerm user configuration"
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
        font_size = 13;
        window_background_opacity = 0.95;
        hide_tab_bar_if_only_one_tab = true;
      };
      description = ''
        Rendered into {file}`$XDG_CONFIG_HOME/wezterm/wezterm.lua` as
        `config.<key> = <value>` lines. Values may be strings, numbers, booleans,
        lists, or shallow attrsets (mapped to Lua tables). itera's opinionated
        defaults are merged underneath via `mkDefault`, so anything set here wins.
        The font is set via {option}`fontFamily`, not here; use {option}`extraLua`
        for anything that needs real Lua (function calls, conditionals).
      '';
    };

    fontFamily = mkOption {
      type = nullOr str;
      default = "JetBrainsMono Nerd Font";
      description = ''
        Font family for WezTerm (`config.font = wezterm.font(...)`). Defaults to
        the JetBrains Mono Nerd Font installed by the system terminal battery, so
        the shell's Nerd-Font glyphs render. Set to `null` to leave WezTerm on its
        built-in default font.
      '';
    };

    extraLua = mkOption {
      type = lines;
      default = "";
      description = ''
        Arbitrary Lua appended to the generated config just before `return config`
        (the `wezterm` module and `config` table are already in scope). Escape
        hatch for anything the declarative options don't cover.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Warn (don't fail) if the home config is on but the system terminal is off —
    # the config would be written for a WezTerm that isn't installed.
    warnings = lib.optional (!systemEnabled) ''
      itera.programs.wezterm is enabled for a user but
      itera.desktop.terminal.enable is false — the WezTerm config will be written
      to $HOME without the terminal being installed.
    '';

    # Opinionated "batteries-included" defaults; explicit user values override.
    itera.programs.wezterm.settings = {
      font_size = mkDefault 12;
      default_cursor_style = mkDefault "SteadyBlock";
      window_padding = mkDefault {
        left = 8;
        right = 8;
        top = 8;
        bottom = 8;
      };
    };

    xdg.config.files."wezterm/wezterm.lua" = {
      text = configText;
      # Explicit clobber — same rationale as the mango battery's config.conf.
      clobber = true;
    };
  };
}
