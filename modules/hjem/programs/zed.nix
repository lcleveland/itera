# itera's Zed user-config renderer (home layer).
#
# The system battery `itera.desktop.editor` installs Zed, claims the text-file MIME
# handlers, and wires the mango `SUPER+e` bind; the curated-program registration
# `modules/programs/zed.nix` declares the settings (system-wide `itera.programs.zed.*`
# + per-user `itera.users.<name>.programs.zed.*`). THIS battery is the renderer: it
# reads the merged result out of `osConfig` and writes `~/.config/zed/settings.json`.
#
# Config format: Zed's config is JSON, rendered with nixpkgs' `pkgs.formats.json`
# generator. Merge model: `systemDefaults // perUserSettings`, shallow per key.
# The dedicated `agent` / `agentServers` options are merged the same way and
# spliced into settings.json under the `agent` / `agent_servers` keys. A per-user
# `clobber = false` (default true) lets Zed's GUI own the file after first write.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `pkgs` / `name` are module args.
# Declares NO options (the schema lives in the registration); enablement follows the
# system editor toggle.
{
  lib,
  iteraLib,
  pkgs,
  osConfig ? null,
  name,
  programs,
  ...
}:
let
  inherit (lib.modules) mkIf;

  json = pkgs.formats.json { };

  enable = osConfig.itera.desktop.editor.enable or false;

  cfg = programs.zed.resolve osConfig name;

  # Layer the resolved settings over the look's defaults, then splice the agent options into their settings.json keys
  # (`agent` / `agent_servers`). `optionalAttrs` keeps empty options from writing
  # an empty `{}` into the file.
  # The look's fonts are defaults; `settings` wins. Zed sizes are pixels, the
  # tokens are points.
  look = iteraLib.look.resolve osConfig name;
  px = pt: builtins.floor (pt * 4 / 3.0 + 0.5);
  baseSettings = {
    buffer_font_family = look.fonts.mono;
    buffer_font_size = px look.fonts.size.mono;
    ui_font_family = look.fonts.sans;
    ui_font_size = px look.fonts.size.sans;
  }
  // cfg.settings;
  inherit (cfg) agent agentServers;
  finalSettings =
    baseSettings
    // (lib.optionalAttrs (agent != { }) { inherit agent; })
    // (lib.optionalAttrs (agentServers != { }) { agent_servers = agentServers; });

  # Concrete bool (never null): a per-user opt-out lets Zed's GUI own the file
  # after first write (see the registration's `clobber` doc). Mirrors the DMS
  # battery.
  inherit (cfg) clobber;

  # Zed's theme stays the DMS one while DMS is on (docs/look.md#verification):
  # any theme but DMS's DankShell pair would ignore the look.
  isDankTheme =
    t:
    if builtins.isString t then
      lib.hasPrefix "DankShell " t
    else
      lib.all isDankTheme (lib.attrValues (removeAttrs t [ "mode" ]));
in
{
  config = mkIf enable {
    assertions = lib.optional (osConfig.itera.desktop.dankMaterialShell.enable or false) {
      assertion = isDankTheme (finalSettings.theme or "DankShell Dark");
      message = "Zed's `theme' (itera.programs.zed.settings or this user's override) names a theme other than DMS's DankShell Dark/Light, so Zed would not follow the look. Remove it, or turn DankMaterialShell off.";
    };

    xdg.config.files."zed/settings.json" = {
      source = json.generate "zed-settings.json" finalSettings;
      inherit clobber;
    };
  };
}
