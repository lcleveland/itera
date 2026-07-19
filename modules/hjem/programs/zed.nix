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

  # Merge the raw settings and the dedicated agent options (system // per-user,
  # shallow per key), then splice the agent options into their settings.json keys
  # (`agent` / `agent_servers`). `optionalAttrs` keeps empty options from writing
  # an empty `{}` into the file.
  baseSettings = (sys.settings or { }) // (usr.settings or { });
  agent = (sys.agent or { }) // (usr.agent or { });
  agentServers = (sys.agentServers or { }) // (usr.agentServers or { });
  finalSettings =
    baseSettings
    // (lib.optionalAttrs (agent != { }) { inherit agent; })
    // (lib.optionalAttrs (agentServers != { }) { agent_servers = agentServers; });

  # Concrete bool (never null): a per-user opt-out lets Zed's GUI own the file
  # after first write (see the registration's `clobber` doc). Mirrors the DMS
  # battery.
  clobber = usr.clobber or true;
in
{
  config = mkIf enable {
    xdg.config.files."zed/settings.json" = {
      source = json.generate "zed-settings.json" finalSettings;
      inherit clobber;
    };
  };
}
