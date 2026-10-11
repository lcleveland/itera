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
# it is on the system PATH and starting it from `exec_once=` keeps the shell's
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
    if (usr.layoutCycle or null) != null then usr.layoutCycle else (sys.layoutCycle or [ ]);

  # per-user-only knobs (fall back to the schema defaults for plain users).
  autostart = usr.autostart or true;
  extraConfig = usr.extraConfig or "";
  useDefaultKeybinds = usr.defaultKeybinds.enable or true;
  useDefaultMousebinds = usr.defaultMousebinds.enable or true;
  useDefaultGestures = usr.defaultGestures.enable or true;

  # Binds: system defaults (unless the user opted out) merged with per-user
  # binds. A per-user bind replaces a default of the same NAME or on the same
  # TRIGGER (modifiers + `triggerOf`) — without the latter, a user bind on a key a default
  # already holds would render both and fail mango's conflict check. Modifier
  # order and case don't matter to mango, so they're normalised here.
  mergeBinds =
    triggerOf: useDefaults: system: user:
    let
      mods = b: lib.sort lib.lessThan (map lib.toUpper (b.modifierKeys or [ ]));
      trigger = b: lib.concatStringsSep "," ([ (lib.concatStringsSep "+" (mods b)) ] ++ triggerOf b);
      userTriggers = lib.mapAttrsToList (_: trigger) user;
    in
    lib.filterAttrs (_: b: !(builtins.elem (trigger b) userTriggers)) (
      lib.optionalAttrs useDefaults system
    )
    // user;

  # What identifies each bind kind's trigger, besides its modifiers.
  keyTrigger = b: [ (lib.toLower b.keySymbol) ];
  gestureTrigger = g: [
    g.direction
    (toString (g.fingerCount or 3))
  ];
  mouseTrigger = m: [ m.button ];

  effectiveKeybinds = mergeBinds keyTrigger useDefaultKeybinds (sys.keybinds or { }) (
    usr.keybinds or { }
  );

  # monitors: system-wide output rules merged with this user's. A per-user
  # monitor of the same key replaces the system entry wholesale; new keys add.
  monitors = (sys.monitors or { }) // (usr.monitors or { });

  # gestures / mouse binds: same merge model as keybinds.
  gestures = mergeBinds gestureTrigger useDefaultGestures (sys.gestures or { }) (usr.gestures or { });
  mousebinds = mergeBinds mouseTrigger useDefaultMousebinds (sys.mousebinds or { }) (
    usr.mousebinds or { }
  );

  # Keyboard layout: driven by the system `itera.keyboard` battery
  # (services.xserver.xkb). Emitting the `xkb_rules_*` lines here keeps the mango
  # session's layout in lockstep with the console/greeter without a per-user knob.
  xkb = osConfig.services.xserver.xkb or { };

  # itera's opinionated startup: bring the systemd/D-Bus user session up (so
  # portals and user services see WAYLAND_DISPLAY etc. and can actually start),
  # start the removable-storage automount agent (when the storage battery is on
  # — udisks2 has no automount of its own), then launch the shell.
  #
  # The session bring-up is one script rather than three `exec_once=` lines
  # because mango spawns each `exec_once` asynchronously: the environment must
  # be in place *before* the target activates, or the units it pulls in inherit
  # an empty one. mango does export the session variables itself these days
  # (`set_activation_env()` in mango.c, issued just before the exec_once list),
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
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE NIXOS_OZONE_WL \
      XCURSOR_THEME XCURSOR_SIZE
    ${pkgs.systemd}/bin/systemctl --user reset-failed
    ${pkgs.systemd}/bin/systemctl --user start mango-session.target
  '';

  autostartUdiskie = (osConfig.itera.storage.enable or false) && (osConfig.itera.enable or false);
  autostartConfig = lib.concatStringsSep "\n" (
    [ "exec_once=${sessionSetup}" ]
    ++ lib.optional autostartUdiskie "exec_once=${pkgs.udiskie}/bin/udiskie --automount --tray"
    # systemd-cat so the shell's output lands in the journal (`journalctl --user -t dms`).
    ++ [ "exec_once=${pkgs.systemd}/bin/systemd-cat -t dms dms run" ]
  );

  # DankMaterialShell writes the look-and-feel it manages (theme colors, gaps,
  # borders, cursor, touchpad/keyboard input, display layout, window rules) as
  # fragments under mango/dms/ and expects config.conf to source them.
  # `source_optional` so a fresh account (before DMS first runs) and the
  # build-time `mango -p` check, which has no such files, parse cleanly.
  # Placed after itera's monitor rules (mango applies the FIRST matching rule,
  # so itera's monitors win) and before xkb/layout (later scalar lines win, so
  # itera's keyboard layout and tag layouts win). `dms/binds.conf` is left out:
  # DMS's binds would collide with itera's and trip mango's conflict check.
  dmsSourcesConfig = lib.optionalString (osConfig.itera.desktop.dankMaterialShell.enable or false) (
    lib.concatMapStringsSep "\n" (f: "source_optional=./dms/${f}.conf") [
      "colors"
      "layout"
      "cursor"
      "input"
      "outputs"
      "windowrules"
    ]
  );

  # itera's opinionated compositor options (mango defaults otherwise).
  #
  # focus_cross_monitor: directional focus (SUPER+h/j/k/l, 3-finger swipes) at
  # the edge of a tag moves to the monitor that way instead of doing nothing. A
  # same-monitor window always wins, so the scroller strip is walked end to end
  # first; single-monitor machines are unaffected. Swaps stay per-monitor
  # (that is `exchange_cross_monitor`, left off). `focus_cross_tag` stays off:
  # in scroller most columns have nothing above/below, so j/k would switch tags.
  # Override either in `extraConfig` (later lines win).
  optionsConfig = "focus_cross_monitor=1";

  keybindsConfig = iteraLib.mango.renderKeybinds effectiveKeybinds;
  gesturesConfig = iteraLib.mango.renderGestures gestures;
  mouseBindsConfig = iteraLib.mango.renderMouseBinds mousebinds;
  monitorsConfig = iteraLib.mango.renderMonitorRules monitors;
  xkbConfig = iteraLib.mango.renderXkb {
    layout = xkb.layout or "";
    variant = xkb.variant or "";
    options = xkb.options or "";
  };

  # Tiling layout: the per-tag default (`tag_rule` lines) plus the `circle_layout`
  # cycle list.
  layoutConfig = lib.concatStringsSep "\n" (
    lib.filter (line: line != "") [
      (iteraLib.mango.mkTagLayoutLines { inherit layout; })
      (iteraLib.mango.mkCircleLayoutLine layoutCycle)
    ]
  );

  # Order: autostart (exec_once) → monitors → DMS fragments → xkb → layout →
  # options → keybinds → mousebinds → gestures → freeform extraConfig. Order
  # matters twice: mango applies the FIRST matching monitor rule, so itera's
  # rules precede DMS's outputs fragment; and later scalar lines win, so
  # itera's xkb/options follow the DMS fragments and extraConfig comes last.
  configText = lib.concatStringsSep "\n" (
    lib.optional autostart autostartConfig
    ++ lib.optional (monitorsConfig != "") monitorsConfig
    ++ lib.optional (dmsSourcesConfig != "") dmsSourcesConfig
    ++ lib.optional (xkbConfig != "") xkbConfig
    ++ lib.optional (layoutConfig != "") layoutConfig
    ++ [ optionsConfig ]
    ++ lib.optional (keybindsConfig != "") keybindsConfig
    ++ lib.optional (mouseBindsConfig != "") mouseBindsConfig
    ++ lib.optional (gesturesConfig != "") gesturesConfig
    ++ lib.optional (extraConfig != "") extraConfig
  );
in
{
  config = mkIf enable {
    xdg.config.files."mango/config.conf" = mkIf (configText != "") {
      # Parsed with `mango -p` at build time (as upstream's home-manager module
      # does): an unknown key (e.g. after an upstream rename, which mango ships
      # without aliases) or a keybind conflict fails the rebuild instead of being
      # skipped at runtime.
      source = iteraLib.mango.validateConfig {
        inherit pkgs;
        mango = osConfig.programs.mango.package;
        text = configText + "\n";
      };
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
