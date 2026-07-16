# Curated-program registration for WezTerm (the terminal battery's home config).
#
# Declares WezTerm's curated options ONCE and exposes them at two levels:
#   - `itera.programs.wezterm.*`               — system-wide default for every user
#   - `itera.users.<name>.programs.wezterm.*`  — per-user override (wins per key)
#
# The hjem battery `modules/hjem/programs/wezterm.nix` reads the merged result via
# `osConfig` and renders `~/.config/wezterm/wezterm.lua`.
#
# See lib/programs.nix for the framework. NOT a NixOS module — a registration
# record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.modules) mkDefault;
  inherit (lib.types)
    attrsOf
    anything
    str
    nullOr
    lines
    ;
in
iteraLib.programs.mkCuratedProgram {
  name = "wezterm";

  fields = {
    settings = {
      type = attrsOf anything;
      attrs = true;
      example = {
        font_size = 13;
        window_background_opacity = 0.95;
        hide_tab_bar_if_only_one_tab = true;
      };
      description = ''
        Rendered into {file}`$XDG_CONFIG_HOME/wezterm/wezterm.lua` as
        `config.<key> = <value>` lines. Values may be strings, numbers, booleans,
        lists, or shallow attrsets (mapped to Lua tables). System-wide default
        ({option}`itera.programs.wezterm.settings`) and per-user overrides merge
        per key. The font is set via `fontFamily`; use `extraLua` for real Lua.
      '';
    };

    fontFamily = {
      type = nullOr str;
      default = "JetBrainsMono Nerd Font";
      description = ''
        Font family for WezTerm (`config.font = wezterm.font(...)`). Defaults to the
        JetBrains Mono Nerd Font installed by the terminal battery. A system-wide
        `null` leaves WezTerm on its built-in default font.
      '';
    };

    extraLua = {
      type = lines;
      default = "";
      description = ''
        Arbitrary Lua appended to the generated config just before `return config`
        (the `wezterm` module and `config` table are already in scope).
      '';
    };
  };

  # Opinionated "batteries-included" defaults; explicit values override.
  systemConfig = _: {
    settings = {
      font_size = mkDefault 12;
      default_cursor_style = mkDefault "SteadyBlock";
      window_padding = mkDefault {
        left = 8;
        right = 8;
        top = 8;
        bottom = 8;
      };
    };
  };
}
