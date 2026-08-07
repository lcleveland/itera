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
# A bare wlroots compositor launched by greetd brings up no systemd user session
# of its own, so this battery's first autostart entry does it: it exports the
# session environment and starts `mango-session.target`, which is bound to
# {file}`graphical-session.target` (see `modules/nixos/desktop/mango.nix`).
# xdg-desktop-portal 1.22+ refuses to start without that target, so this is what
# keeps portals — file pickers, screencast, the color-scheme preference — alive.
#
# `dms` is still spawned directly rather than through DMS's systemd user service:
# it is on the system PATH and starting it from `exec-once=` keeps the shell's
# lifetime tied to the compositor without depending on unit ordering.
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

  # gestures: same merge model as keybinds/monitors (system default set, per-user
  # entry of the same name replaces, new names add).
  gestures = (sys.gestures or { }) // (usr.gestures or { });

  # Keyboard layout: driven by the system `itera.keyboard` battery
  # (services.xserver.xkb). Emitting the `xkb_rules_*` lines here keeps the mango
  # session's layout in lockstep with the console/greeter without a per-user knob.
  xkb = osConfig.services.xserver.xkb or { };

  # itera's opinionated startup: bring the systemd/D-Bus user session up (so
  # portals and user services see WAYLAND_DISPLAY etc. and can actually start),
  # start the removable-storage automount agent (when the storage battery is on
  # — udisks2 has no automount of its own), then launch the shell.
  #
  # The session bring-up is one script rather than three `exec-once=` lines
  # because mango spawns each `exec-once` asynchronously: the environment must
  # be in place *before* the target activates, or the units it pulls in inherit
  # an empty one. mango does export the session variables itself these days
  # (`set_activation_env()` in mango.c, issued just before the exec-once list),
  # but it too is an async spawn and its fixed variable list omits NixOS's
  # `NIXOS_OZONE_WL`, so doing it here keeps the ordering deterministic.
  #
  # `mango-session.target` is declared by the system battery
  # (`modules/nixos/desktop/mango.nix`) and is bound to
  # `graphical-session.target`, so starting it activates the target that
  # xdg-desktop-portal 1.22+ requires. `reset-failed` first, so units left
  # failed by a previous session on this user manager can start again.
  sessionSetup = pkgs.writeShellScript "itera-mango-session-setup" ''
    ${pkgs.dbus}/bin/dbus-update-activation-environment --all
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE NIXOS_OZONE_WL
    ${pkgs.systemd}/bin/systemctl --user reset-failed
    ${pkgs.systemd}/bin/systemctl --user start mango-session.target
  '';

  autostartUdiskie = (osConfig.itera.storage.enable or false) && (osConfig.itera.enable or false);
  autostartConfig = lib.concatStringsSep "\n" (
    [ "exec-once=${sessionSetup}" ]
    ++ lib.optional autostartUdiskie "exec-once=${pkgs.udiskie}/bin/udiskie --automount --tray"
    ++ [ "exec-once=dms run" ]
  );

  keybindsConfig = iteraLib.mango.renderKeybinds effectiveKeybinds;
  gesturesConfig = iteraLib.mango.renderGestures gestures;
  monitorsConfig = iteraLib.mango.renderMonitorRules monitors;
  xkbConfig = iteraLib.mango.renderXkb {
    layout = xkb.layout or "";
    variant = xkb.variant or "";
    options = xkb.options or "";
  };

  # Tiling layout: the per-tag default (`tagrule` lines) plus the `circle_layout`
  # cycle list.
  layoutConfig = lib.concatStringsSep "\n" (
    lib.filter (line: line != "") [
      (iteraLib.mango.mkTagLayoutLines { inherit layout; })
      (iteraLib.mango.mkCircleLayoutLine layoutCycle)
    ]
  );

  # Order: autostart (exec-once) → monitors → xkb → layout → keybinds → gestures
  # → freeform extraConfig. (mango matches monitor rules by name, so their
  # position in the file is not significant — placed early for readability.)
  configText = lib.concatStringsSep "\n" (
    lib.optional autostart autostartConfig
    ++ lib.optional (monitorsConfig != "") monitorsConfig
    ++ lib.optional (xkbConfig != "") xkbConfig
    ++ lib.optional (layoutConfig != "") layoutConfig
    ++ lib.optional (keybindsConfig != "") keybindsConfig
    ++ lib.optional (gesturesConfig != "") gesturesConfig
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
