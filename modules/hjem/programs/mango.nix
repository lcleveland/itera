# itera's mango user-config renderer (home layer).
#
# The system battery `itera.desktop.mango` installs the compositor and registers
# its session; the curated-program registration `modules/programs/mango.nix`
# declares the tunable options (system-wide `itera.programs.mango.*` + per-user
# `itera.users.<name>.programs.mango.*`). THIS battery is the renderer: it reads
# the merged result out of `osConfig` and writes the per-user
# {file}`$XDG_CONFIG_HOME/mango/config.conf` — most importantly the autostart lines
# that launch DankMaterialShell inside the session.
#
# Why autostart `dms` here rather than via DMS's systemd user service: a bare
# wlroots compositor launched by greetd does not bring up
# {file}`graphical-session.target` on its own, so the DMS systemd unit would never
# start. mango runs `exec-once=` commands on startup and `dms` is on the system
# PATH, so spawning it directly is the reliable path.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`), so sinks
# like `xdg.config.files` are written unprefixed, `osConfig`/`pkgs`/`iteraLib` are
# module args, and `name` is the username. This battery declares NO options — the
# schema lives in the registration; enablement follows the system compositor toggle.
{
  lib,
  pkgs,
  iteraLib,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.mango.enable or false;

  # System-wide defaults (itera.programs.mango) and this user's overrides
  # (itera.users.<name>.programs.mango). A user declared the plain NixOS way has
  # no `itera.users.<name>` entry, so `usr` is empty and the system defaults apply.
  sys = osConfig.itera.programs.mango or { };
  usr = osConfig.itera.users.${name}.programs.mango or { };

  # scalar/list overrides: per-user value wins when set (non-null), else system.
  layout = if (usr.layout or null) != null then usr.layout else (sys.layout or "scroller");
  layoutCycle =
    if (usr.layoutCycle or null) != null then
      usr.layoutCycle
    else
      (sys.layoutCycle or [
        "scroller"
        "tile"
        "monocle"
        "grid"
      ]
      );

  # per-user-only knobs (fall back to the schema defaults for plain users).
  autostart = usr.autostart or true;
  extraConfig = usr.extraConfig or "";
  useDefaultKeybinds = usr.defaultKeybinds.enable or true;

  # keybinds: system defaults (unless the user opted out) merged with per-user
  # binds. A per-user bind of the same name replaces the default; new names add.
  systemKeybinds = sys.keybinds or { };
  userKeybinds = usr.keybinds or { };
  effectiveKeybinds = (lib.optionalAttrs useDefaultKeybinds systemKeybinds) // userKeybinds;

  # monitors: system-wide output rules merged with this user's. A per-user
  # monitor of the same key replaces the system entry wholesale; new keys add.
  monitors = (sys.monitors or { }) // (usr.monitors or { });

  # itera's opinionated startup: refresh the D-Bus/systemd user environment (so
  # portals and user services see WAYLAND_DISPLAY etc.), start the removable-
  # storage automount agent (when the storage battery is on — udisks2 has no
  # automount of its own), then launch the shell.
  autostartUdiskie = (osConfig.itera.storage.enable or false) && (osConfig.itera.enable or false);
  autostartConfig = lib.concatStringsSep "\n" (
    [ "exec-once=${pkgs.dbus}/bin/dbus-update-activation-environment --all" ]
    ++ lib.optional autostartUdiskie "exec-once=${pkgs.udiskie}/bin/udiskie --automount --tray"
    ++ [ "exec-once=dms run" ]
  );

  keybindsConfig = iteraLib.mango.renderKeybinds effectiveKeybinds;
  monitorsConfig = iteraLib.mango.renderMonitorRules monitors;

  # Tiling layout: the per-tag default (`tagrule` lines) plus the `circle_layout`
  # cycle list.
  layoutConfig = lib.concatStringsSep "\n" (
    lib.filter (line: line != "") [
      (iteraLib.mango.mkTagLayoutLines { inherit layout; })
      (iteraLib.mango.mkCircleLayoutLine layoutCycle)
    ]
  );

  # Order: autostart (exec-once) → monitors → layout → keybinds → freeform
  # extraConfig. (mango matches monitor rules by name, so their position in the
  # file is not significant — placed early for readability.)
  configText = lib.concatStringsSep "\n" (
    lib.optional autostart autostartConfig
    ++ lib.optional (monitorsConfig != "") monitorsConfig
    ++ lib.optional (layoutConfig != "") layoutConfig
    ++ lib.optional (keybindsConfig != "") keybindsConfig
    ++ lib.optional (extraConfig != "") extraConfig
  );
in
{
  config = mkIf enable {
    xdg.config.files."mango/config.conf" = mkIf (configText != "") {
      source = pkgs.writeText "mango-config.conf" (configText + "\n");
      # Explicit clobber (beyond itera's `hjem.clobberByDefault = true`) so the
      # linker OVERWRITES an existing target instead of leaving it. Two reasons:
      # (1) under itera's impermanence ~/.config is restored from /persist every
      # boot, so a non-clobber file freezes at its first-ever link target; and
      # (2) setting it here changes this entry in smfh's manifest, which forces
      # smfh's diff to treat it as "updated" and re-link it — healing a symlink
      # already stranded on a stale target (e.g. the old `spawn,ghostty` bind)
      # on the next rebuild, which flipping only the global default would not do.
      clobber = true;
    };
  };
}
