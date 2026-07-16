# itera's WezTerm user-config renderer (home layer).
#
# The system battery `itera.desktop.terminal` installs WezTerm (+ JetBrains Mono
# Nerd Font) and wires the mango `SUPER+t` bind; the curated-program registration
# `modules/programs/wezterm.nix` declares the options (system-wide
# `itera.programs.wezterm.*` + per-user `itera.users.<name>.programs.wezterm.*`).
# THIS battery is the renderer: it reads the merged result out of `osConfig` and
# writes `~/.config/wezterm/wezterm.lua`.
#
# Config format: WezTerm's config is Lua — a script that builds and returns a config
# table. `settings` is rendered as `config.<key> = <lua-value>` via a small local
# `toLua` serializer (scalars, lists, shallow tables); `fontFamily` is special-cased
# (a `wezterm.font(...)` call) and `extraLua` is an escape hatch for arbitrary Lua.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `name` are module args. Declares
# NO options (the schema lives in the registration); enablement follows the system
# terminal toggle.
{
  lib,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.terminal.enable or false;

  sys = osConfig.itera.programs.wezterm or { };
  usr = osConfig.itera.users.${name}.programs.wezterm or { };

  finalSettings = (sys.settings or { }) // (usr.settings or { });
  # scalar overrides: per-user value wins when set (non-null), else system.
  fontFamily = if (usr.fontFamily or null) != null then usr.fontFamily else (sys.fontFamily or null);
  extraLua = if (usr.extraLua or null) != null then usr.extraLua else (sys.extraLua or "");

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
    lib.mapAttrsToList (k: v: "config.${k} = ${toLua v}") finalSettings
  );

  fontLua = lib.optionalString (fontFamily != null) "config.font = wezterm.font('${fontFamily}')";

  configText = ''
    local wezterm = require 'wezterm'
    local config = wezterm.config_builder()

    ${settingsLua}
    ${fontLua}
    ${extraLua}

    return config
  '';
in
{
  config = mkIf enable {
    xdg.config.files."wezterm/wezterm.lua" = {
      text = configText;
      # Explicit clobber — same rationale as the mango battery's config.conf.
      clobber = true;
    };
  };
}
