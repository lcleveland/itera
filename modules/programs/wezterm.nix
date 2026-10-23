# Curated-program registration for WezTerm (the terminal battery's home config).
#
# Declares WezTerm's curated options ONCE and exposes them at two levels:
#   - `itera.programs.wezterm.*`               — system-wide default for every user
#   - `itera.users.<name>.programs.wezterm.*`  — per-user override (wins per key)
#
# The hjem battery `modules/hjem/programs/wezterm.nix` reads the merged result via
# `osConfig` and renders `~/.config/wezterm/wezterm.lua`. Font, size and opacity
# defaults come from the look there.
#
# See lib/programs.nix for the framework. NOT a NixOS module — a registration
# record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkDefault mkRemovedOptionModule;
  inherit (lib.types)
    attrsOf
    anything
    nullOr
    lines
    ;

  # The removed `fontFamily` option (docs/look.md#migration). Drop both shims
  # at NixOS 26.11, the next stable release after they landed.
  fontFamilyRemoved = "Set the look's mono font, look.fonts.mono (system-wide or per user), instead.";

  reg = iteraLib.programs.mkCuratedProgram {
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
          per key. `font_size` and `window_background_opacity` default to the
          look's mono size and opacity, and `font` (a family name, rendered as
          `wezterm.font(...)`) to the look's mono font. Use `extraLua` for real Lua.
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
        default_cursor_style = mkDefault "SteadyBlock";
        window_padding = mkDefault {
          left = 8;
          right = 8;
          top = 8;
          bottom = 8;
        };
      };
    };
  };
in
{
  inherit (reg) name resolve;

  systemModule =
    { config, ... }:
    {
      imports = [
        reg.systemModule
        (mkRemovedOptionModule [ "itera" "programs" "wezterm" "fontFamily" ] fontFamilyRemoved)
      ];
      # The per-user shim: submodules have no `assertions`, so it is checked here.
      assertions = lib.mapAttrsToList (n: u: {
        assertion = u.programs.wezterm.fontFamily == null;
        message = "The option `itera.users.${n}.programs.wezterm.fontFamily' no longer has any effect; please remove it.\n${fontFamilyRemoved}";
      }) config.itera.users;
    };

  usersSubmodule = {
    imports = [ reg.usersSubmodule ];
    options.programs.wezterm.fontFamily = mkOption {
      type = nullOr anything;
      default = null;
      visible = false;
      description = "Removed. ${fontFamilyRemoved}";
    };
  };
}
