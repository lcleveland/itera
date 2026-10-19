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
# `dms` itself runs as DMS's systemd user service, wanted by
# `mango-session.target` (set up by the desktop battery), so starting the target
# starts the shell and a crash restarts it. With that service turned off the shell
# falls back to a plain `exec_once=`.
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
  scrollerFocusCenter =
    if (usr.scrollerFocusCenter or null) != null then
      usr.scrollerFocusCenter
    else
      (sys.scrollerFocusCenter or true);

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
  monitors = iteraLib.mango.userMonitors osConfig name;

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
  # `MANGO_INSTANCE_SIGNATURE` matters to DMS: its mango colour template
  # (dms/colors.conf) only renders when the variable names a live socket.
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
      XCURSOR_THEME XCURSOR_SIZE MANGO_INSTANCE_SIGNATURE
    ${pkgs.systemd}/bin/systemctl --user reset-failed
    ${pkgs.systemd}/bin/systemctl --user start mango-session.target
  '';

  autostartUdiskie = (osConfig.itera.storage.enable or false) && (osConfig.itera.enable or false);

  # udiskie's tray icon. Left alone it resolves a drive icon from the Qt icon
  # theme (Adwaita), which looks nothing like the DMS bar around it; DMS draws its
  # own icons from Material Symbols Rounded. This is that font's `usb` glyph
  # (Apache-2.0, google/material-design-icons) filled with
  # `itera.storage.trayIconColor`, else this user's look `text` colour in their
  # starting mode (auto starts dark). Qt doesn't recolor icons, so the fill is
  # baked in.
  look = iteraLib.look.resolve osConfig name;
  trayIconColor =
    if osConfig.itera.storage.trayIconColor or null != null then
      osConfig.itera.storage.trayIconColor
    else
      look.startColors.text;
  udiskieIcon = pkgs.writeText "udiskie-tray-icon.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path fill="${trayIconColor}" d="M480-80q-33 0-56.5-23.5T400-160q0-21 11-39t29-29v-92H320q-33 0-56.5-23.5T240-400v-92q-18-9-29-27t-11-41q0-33 23.5-56.5T280-640q33 0 56.5 23.5T360-560q0 23-11 40t-29 28v92h120v-320h-40q-12 0-18-11t2-21l80-107q6-8 16-8t16 8l80 107q8 10 2 21t-18 11h-40v320h120v-80h-20q-8 0-14-6t-6-14v-120q0-8 6-14t14-6h120q8 0 14 6t6 14v120q0 8-6 14t-14 6h-20v80q0 33-23.5 56.5T640-320H520v92q19 10 29.5 28t10.5 40q0 33-23.5 56.5T480-80Z"/></svg>
  '';
  # udiskie accepts a file path in `icon_names`, and DMS's tray loads a path icon
  # as a file. `-c` means a ~/.config/udiskie/config.yml is not read.
  udiskieConfig = pkgs.writeText "udiskie-config.yml" ''
    icon_names:
      media:
        - ${udiskieIcon}
  '';

  autostartConfig = lib.concatStringsSep "\n" (
    [ "exec_once=${sessionSetup}" ]
    ++ lib.optional autostartUdiskie "exec_once=${pkgs.udiskie}/bin/udiskie --automount --tray -c ${udiskieConfig}"
    # systemd-cat so the shell's output lands in the journal (`journalctl --user -t dms`).
    ++ lib.optional (
      !(osConfig.programs.dank-material-shell.systemd.enable or false)
    ) "exec_once=${pkgs.systemd}/bin/systemd-cat -t dms dms run"
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
  # The look's starting cursor (the cursor battery). mango exports XCURSOR_*
  # from it, so the session gets this user's cursor even before DMS first writes
  # dms/cursor.conf, which is sourced after it and wins once it exists.
  cursorConfig = lib.optionalString (
    (osConfig.itera.enable or false) && (osConfig.itera.desktop.cursor.enable or false)
  ) "cursor_theme=${look.cursor.name.${look.startMode}}\ncursor_size=${toString look.cursor.size}";

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
  #
  # border_radius: the look's radius (docs/look.md#delivery-lanes), after the
  # DMS fragments so it wins over DMS's layout.conf.
  #
  # scroller_focus_center: the curated `scrollerFocusCenter` knob (on by default).
  optionsConfig = ''
    focus_cross_monitor=1
    border_radius=${toString look.radius}
    scroller_focus_center=${if scrollerFocusCenter then "1" else "0"}'';

  keybindsConfig = iteraLib.mango.renderKeybinds effectiveKeybinds;
  gesturesConfig = iteraLib.mango.renderGestures gestures;
  mouseBindsConfig = iteraLib.mango.renderMouseBinds mousebinds;
  monitorsConfig = iteraLib.mango.renderMonitorRules monitors;
  xkbConfig = iteraLib.mango.renderXkb {
    layout = xkb.layout or "";
    variant = xkb.variant or "";
    options = xkb.options or "";
  };

  # Tiling layout: the per-tag default (`tag_rule` lines), the `circle_layout`
  # cycle list, the look's scroller cycle presets, and per-monitor scroller
  # proportions by aspect class (docs/look.md#ultrawide). The class rules come
  # after the per-tag defaults; mango applies every matching tag_rule in order.
  layoutConfig = lib.concatStringsSep "\n" (
    lib.filter (line: line != "") [
      (iteraLib.mango.mkTagLayoutLines { inherit layout; })
      (iteraLib.mango.mkCircleLayoutLine layoutCycle)
      (iteraLib.mango.mkProportionPresetLine look.layout.presets)
      (iteraLib.mango.mkAspectTagRules look.layout.proportions (iteraLib.mango.declaredOutputs monitors))
    ]
  );

  # Order: autostart (exec_once) → monitors → cursor → DMS fragments → xkb → layout →
  # options → keybinds → mousebinds → gestures → freeform extraConfig. Order
  # matters twice: mango applies the FIRST matching monitor rule, so itera's
  # rules precede DMS's outputs fragment; and later scalar lines win, so
  # itera's xkb/options follow the DMS fragments and extraConfig comes last.
  configText = lib.concatStringsSep "\n" (
    lib.optional autostart autostartConfig
    ++ lib.optional (monitorsConfig != "") monitorsConfig
    ++ lib.optional (cursorConfig != "") cursorConfig
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
