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
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `pkgs` / `name` are module args.
# Declares NO options (the schema lives in the registration); enablement follows the
# system editor toggle.
{
  lib,
  pkgs,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  json = pkgs.formats.json { };

  enable = osConfig.itera.desktop.editor.enable or false;

  sys = osConfig.itera.programs.zed or { };
  usr = osConfig.itera.users.${name}.programs.zed or { };

  finalSettings = (sys.settings or { }) // (usr.settings or { });
in
{
  config = mkIf enable {
    xdg.config.files."zed/settings.json" = {
      source = json.generate "zed-settings.json" finalSettings;
      # Explicit clobber — replace any pre-existing settings.json rather than letting
      # hjem refuse to overwrite (same rationale as the mango battery).
      clobber = true;
    };
  };
}
