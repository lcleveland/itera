# Evaluation check for itera's curated per-program options system:
# the `itera.users` account battery, the system-wide defaults
# (`itera.programs.<app>`) reaching every user, and the per-user overrides
# (`itera.users.<name>.programs.<app>`) winning per key.
#
# Drives TWO users — alice (with overrides) and bob (with none) — so
# "system default reaches the user" is a real assertion, not a tautology. It
# evaluates a NixOS configuration and asserts the generated config, then
# unit-checks the mango keybind/layout renderers directly. `nix build` forces
# evaluation and fails loudly if any assertion is false.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    userFile
    ;

  cfg = mkConfig [
    {
      itera = {
        # System-wide keyboard layout (should reach every mango session + greeter).
        keyboard.variant = "colemak_dh";

        # Claude ACP battery on: with the editor battery on by default, this
        # auto-registers `claude-agent-acp` under Zed's `agent_servers` for every
        # user who does not override it (see bob's assertions below).
        ai.claude.acp.enable = true;

        programs = {
          # A system-wide DMS default override (should reach EVERY user).
          dankMaterialShell.settings.currentThemeName = "blue";

          # System-wide Zed defaults (should reach EVERY user): a raw setting plus
          # a curated agent field spliced into the `agent` settings key.
          zed = {
            settings.buffer_font_size = 14;
            agent.default_profile = "ask";
          };

          mango = {
            # System-wide mango gestures (should reach EVERY user).
            gestures.focusRight = {
              direction = "left";
              fingerCount = 3;
              mangoCommand = "focusdir";
              commandArguments = "right";
            };

            # System-wide monitor rules (should reach EVERY user, and the greeter).
            # The keys default into the `name` match — no explicit `name` set here,
            # so the rendered lines proving `name:HDMI-1` / `name:DP-2` also prove
            # the key→name default.
            monitors = {
              "HDMI-1" = {
                width = 1920;
                height = 1080;
                refresh = 60;
                x = 0;
                y = 0;
              };
              "DP-2" = {
                width = 2560;
                height = 1440;
                refresh = 60;
                x = 1920;
                y = 0;
              };
            };
          };
        };

        users = {
          # alice: account + per-user deviations from the system-wide defaults.
          alice = {
            initialPassword = "changeme";
            # Per-user package escape hatch.
            packages = [ pkgs.hello ];
            programs = {
              dankMaterialShell = {
                settings.radiusStrength = 25;
                # Per-user plugin: a new name adds only for alice.
                plugins.Bar.src = pkgs.emptyDirectory;
                # Per-user disable of the default-on ipIndicator. A per-user entry
                # replaces the system one wholesale, so `src` must be re-supplied.
                plugins.ipIndicator = {
                  enable = false;
                  src = pkgs.emptyDirectory;
                };
              };
              # Per-user Zed: override the auto-registered `claude` ACP agent with a
              # custom wrapper command (must win over the system default under
              # `agent_servers`) and opt the file out of clobbering so the GUI can
              # own it.
              zed = {
                clobber = false;
                settings.vim_mode = true;
                agentServers.claude = {
                  command = "my-acp-wrapper";
                  args = [ ];
                };
              };
              mango = {
                layout = "tile";
                scrollerFocusCenter = false;
                # A NEW name on a key a default holds (SUPER+SHIFT+f, fullscreen),
                # modifiers in a different order: must displace the default
                # rather than render both and trip mango's conflict check.
                keybinds.browserFullscreen = {
                  modifierKeys = [
                    "SHIFT"
                    "SUPER"
                  ];
                  keySymbol = "f";
                  mangoCommand = "spawn";
                  commandArguments = "firefox";
                  flagModifiers = [ "s" ];
                };
                defaultMousebinds.enable = false;
                # Per-user gesture: new name adds alongside the system default.
                gestures.cycleLayout = {
                  modifierKeys = [ "SUPER" ];
                  direction = "up";
                  fingerCount = 4;
                  mangoCommand = "switch_layout";
                };
                keybinds.terminal = {
                  modifierKeys = [ "SUPER" ];
                  keySymbol = "Return";
                  mangoCommand = "spawn";
                  commandArguments = "foot";
                  flagModifiers = [ "s" ];
                };
                # Override HDMI-1 wholesale (new mode + scale + rotation); DP-2 is
                # left untouched so it must still inherit the system-wide rule.
                monitors."HDMI-1" = {
                  width = 3840;
                  height = 2160;
                  refresh = 120;
                  x = 0;
                  y = 0;
                  scale = 1.5;
                  transform = "270";
                };
              };
            };
          };

          # bob: an account with NO per-user overrides — inherits every default.
          bob = { };
        };
      };
    }
  ];

  # Mango without DMS: the media keys must fall back to wpctl/playerctl.
  noDmsMango = userFile (mkConfig [
    {
      itera = {
        desktop.dankMaterialShell.enable = false;
        desktop.mango.enable = true;
        users.carol = { };
      };
    }
  ]) "carol" "mango/config.conf";

  aliceFiles = cfg.hjem.users.alice.xdg.config.files;
  bobFiles = cfg.hjem.users.bob.xdg.config.files;

  json = user: path: builtins.fromJSON (userFile cfg user path);
  aliceDms = json "alice" "DankMaterialShell/config.d/00-itera.json";
  bobDms = json "bob" "DankMaterialShell/config.d/00-itera.json";

  # plugin_settings.json carries the update-indicator plugin's store-path
  # `checkCommand`, which keeps its helper in the closure.
  alicePlugins = json "alice" "DankMaterialShell/plugin_settings.json";
  bobPlugins = json "bob" "DankMaterialShell/plugin_settings.json";

  aliceZed = json "alice" "zed/settings.json";
  bobZed = json "bob" "zed/settings.json";

  aliceMango = userFile cfg "alice" "mango/config.conf";
  bobMango = userFile cfg "bob" "mango/config.conf";

  # The session bring-up is an `exec_once=` pointing at a generated script, so
  # reach through the rendered config to the script itself and assert on its
  # contents — that is where the ordering guarantee actually lives.
  bobSessionSetup = lib.removePrefix "exec_once=" (
    lib.findFirst (l: lib.hasInfix "itera-mango-session-setup" l) "" (lib.splitString "\n" bobMango)
  );

  # The DMS greeter (on by default) runs its own mango instance; itera feeds it
  # the SYSTEM-WIDE monitors via `compositor.customConfig`.
  greeterMonitors = cfg.programs.dms-greeter.compositor.customConfig;

  # What greetd's preStart merges into the greeter's settings.json. Read from
  # the seed, not the written file, so eval builds nothing.
  greeterSettingsOf = c: c.itera.desktop.dankMaterialShell.greeter.seed.settings;
  greeterSettings = greeterSettingsOf cfg;
  greeterWallpaperSettings = greeterSettingsOf (mkConfig [
    { itera.desktop.dankMaterialShell.greeter.wallpaper = "/etc/login-wallpaper.jpg"; }
  ]);

  # Unit-check the keybind renderer directly via the flake's lib output.
  renderedBind = self.lib.mango.renderKeybinds {
    demo = {
      modifierKeys = [
        "SUPER"
        "SHIFT"
      ];
      keySymbol = "q";
      mangoCommand = "quit";
      flagModifiers = [ "s" ];
      description = "Exit mango";
    };
    noMods = {
      keySymbol = "XF86AudioMute";
      mangoCommand = "spawn_shell";
      commandArguments = "true";
      flagModifiers = [ "s" ];
    };
  };

  # Unit-check the monitor renderer directly (plain attrs — no submodule name
  # default, so `name` is given explicitly).
  renderedMonitor = self.lib.mango.renderMonitorRules {
    primary = {
      name = "^eDP-1$";
      width = 1920;
      height = 1080;
      refresh = 59.951;
      scale = 1.5;
      transform = "90";
      vrr = true;
      primary = true;
      hdrMaxLum = 616;
    };
    off = {
      name = "HDMI-2";
      enable = false;
      width = 9999;
    };
  };

  checks = {
    # ── itera.users account battery ──────────────────────────────────────
    "itera.users creates the account" = cfg.users.users.alice.isNormalUser;
    "account has default groups" = builtins.elem "wheel" cfg.users.users.alice.extraGroups;
    "account initialPassword applied" = cfg.users.users.alice.initialPassword == "changeme";
    "hjem enabled for the user" = cfg.hjem.users.alice.enable;
    "second (override-free) account created" = cfg.users.users.bob.isNormalUser;

    # ── DMS settings: system-wide default reaches an un-overridden user ───
    # Pinned to the bundled DMS's schema version so it never migrates.
    "curated system default present (bob)" =
      builtins.isInt bobDms.configVersion && bobDms.configVersion >= 40;
    "idle lock on by default (bob)" = bobDms.acLockTimeout > 0 && bobDms.lockBeforeSuspend;
    "settings.json left to DMS (bob)" = !(bobFiles ? "DankMaterialShell/settings.json");
    "system-level override reaches user (bob)" = bobDms.currentThemeName == "blue";
    "opinionated default present (bob)" = bobDms.clockFormat == "24h";
    "portal sync default present (bob)" = bobDms.syncModeWithPortal == true;
    "weather uses fahrenheit by default (bob)" = bobDms.useFahrenheit == true;
    "weather uses auto location by default (bob)" = bobDms.useAutoLocation == true;

    # ── Zed settings: system defaults reach an un-overridden user (bob) ──
    "zed telemetry-off default present (bob)" = bobZed.telemetry.diagnostics == false;
    # Reaches the written file, not just the option: Zed only honours a named
    # mode, so a dropped `theme` key silently means light.
    "zed dark theme reaches the written settings (bob)" = bobZed.theme.mode == "dark";
    "zed raw system setting reaches user (bob)" = bobZed.buffer_font_size == 14;
    "zed curated agent field reaches user (bob)" = bobZed.agent.default_profile == "ask";
    "zed settings.json clobbers by default (bob)" = bobFiles."zed/settings.json".clobber == true;

    # ── Zed settings: per-user overrides + agents + clobber opt-out (alice) ──
    "zed per-user raw setting applied (alice)" = aliceZed.vim_mode == true;
    "zed system agent field still inherited (alice)" = aliceZed.agent.default_profile == "ask";
    "zed per-user agentServers override wins under agent_servers (alice)" =
      aliceZed.agent_servers.claude.command == "my-acp-wrapper";
    "zed per-user clobber opt-out honored (alice)" = aliceFiles."zed/settings.json".clobber == false;

    # ── Claude ACP auto-registration: system default reaches an un-overridden user
    "zed acp agent auto-registered system-wide" =
      cfg.itera.programs.zed.agentServers.claude.command == "claude-agent-acp";
    "zed acp agent reaches un-overridden user (bob)" =
      bobZed.agent_servers.claude.command == "claude-agent-acp";

    # ── DMS settings: per-user override wins PER KEY, siblings still inherit ──
    "per-user override merges per key (alice)" = aliceDms.radiusStrength == 25;
    "sibling key still inherited (alice)" = aliceDms.clockFormat == "24h";
    "system-level override still inherited (alice)" = aliceDms.currentThemeName == "blue";

    # ── DMS plugins: default-on plugin ships for every user ──────────────
    # ipIndicator is shipped by the desktop battery with enable defaulting to
    # true, so an un-overridden user gets both the plugin dir and enabled=true.
    "default plugin dir shipped (bob)" = bobFiles ? "DankMaterialShell/plugins/ipIndicator";
    "default plugin enabled in plugin_settings (bob)" = bobPlugins.ipIndicator.enabled == true;
    # Enabling only registers the plugin — the widget renders only when placed in
    # a bar config, so assert the shipped default bar references it.
    "default bar places ipIndicator widget (bob)" =
      builtins.elem "ipIndicator" (builtins.head bobDms.barConfigs).rightWidgets;

    # The update indicator ships the same way, but its settings are the whole
    # point: the widget compares a revision baked in here at build time, so a
    # dropped key leaves the pill with nothing to say.
    "update indicator plugin dir shipped (bob)" = bobFiles ? "DankMaterialShell/plugins/iteraUpdate";
    "update indicator enabled in plugin_settings (bob)" = bobPlugins.iteraUpdate.enabled == true;
    "update indicator check command reaches the rendered settings (bob)" =
      lib.hasInfix "itera-update-check" bobPlugins.iteraUpdate.checkCommand;
    "default bar places iteraUpdate widget (bob)" =
      builtins.elem "iteraUpdate" (builtins.head bobDms.barConfigs).rightWidgets;

    # ── DMS plugins: per-user add stays isolated ─────────────────────────
    "per-user plugin present (alice)" = aliceFiles ? "DankMaterialShell/plugins/Bar";
    "per-user plugin not leaked to other user (bob)" = !(bobFiles ? "DankMaterialShell/plugins/Bar");

    # ── DMS plugins: per-user disable of a default plugin ────────────────
    "per-user disable drops plugin dir (alice)" =
      !(aliceFiles ? "DankMaterialShell/plugins/ipIndicator");
    "per-user disable reflected in plugin_settings (alice)" = alicePlugins.ipIndicator.enabled == false;

    # ── mango keybinds: system defaults reach every user ─────────────────
    "default keybind rendered (alice)" = lib.hasInfix "binds=SUPER,q,killclient," aliceMango;
    "default keybind rendered (bob)" = lib.hasInfix "binds=SUPER,q,killclient," bobMango;
    # viewTag stays a keysym bind (SUPER+digit yields the digit keysym).
    "view-tag keybind rendered (keysym)" = lib.hasInfix "binds=SUPER,1,view,1" bobMango;
    # moveToTag must be a keycode bind: SHIFT+digit emits a punctuation keysym,
    # so a keysym bind (`binds=`) would never fire. Guard against regressing to `s`.
    "move-to-tag keybind rendered (keycode)" = lib.hasInfix "bind=SUPER+SHIFT,1,tag,1" bobMango;
    "move-to-tag is not a keysym bind" = !(lib.hasInfix "binds=SUPER+SHIFT,1,tag" bobMango);
    # With DMS the media keys go through its IPC (OSD, DDC brightness) and carry
    # `l` so they work on the lock screen.
    "volume keys go through DMS, also when locked" =
      lib.hasInfix "bindsl=none,XF86AudioRaiseVolume,spawn_shell,dms ipc call audio increment" bobMango;
    "mic mute key bound" = lib.hasInfix "bindsl=none,XF86AudioMicMute," bobMango;
    "keybind cheatsheet label rendered" =
      lib.hasInfix "# Keyboard shortcuts\nbind=SUPER+SHIFT,slash," bobMango;
    # Without DMS the volume keys must call a tool the system actually ships.
    # `pactl` lives in pkgs.pulseaudio, which a PipeWire host never installs, so
    # a pactl bind is a silent no-op; `wpctl` comes with WirePlumber, which is on
    # whenever PipeWire is. Guard both directions so a regression cannot slip back.
    "volume up falls back to wpctl" =
      lib.hasInfix "bindsl=none,XF86AudioRaiseVolume,spawn_shell,wpctl set-volume" noDmsMango;
    "volume mute falls back to wpctl" =
      lib.hasInfix "bindsl=none,XF86AudioMute,spawn_shell,wpctl set-mute" noDmsMango;
    "no DMS binds without DMS" = !(lib.hasInfix "dms ipc" noDmsMango);
    "no keybind shells out to pactl" =
      !(lib.hasInfix "pactl" bobMango) && !(lib.hasInfix "pactl" noDmsMango);
    "dms keybind rendered (desktop on)" = lib.hasInfix "dms ipc call spotlight toggle" bobMango;
    # Browser battery (opt-out, ON by default) wires SUPER+b to launch vivaldi.
    "browser keybind launches vivaldi" = lib.hasInfix "binds=SUPER,b,spawn,vivaldi" bobMango;
    # Calculator battery (opt-out, ON by default) wires SUPER+c AND the bare
    # XF86Calculator key. The dedicated key must render with `none` as its
    # modifier — rendering it as `SUPER+XF86Calculator` would mean the key alone
    # does nothing, which is the whole point of claiming it.
    "calculator keybind launches gnome-calculator" =
      lib.hasInfix "binds=SUPER,c,spawn,gnome-calculator" bobMango;
    "calculator key needs no modifier" =
      lib.hasInfix "binds=none,XF86Calculator,spawn,gnome-calculator" bobMango;
    # The shell runs as DMS's systemd user service (wanted by mango-session.target),
    # not an exec_once, and stays out of the greeter's session.
    "dms not autostarted by mango" = !(lib.hasInfix "dms run" bobMango);
    "dms user service bound to the mango session" =
      cfg.systemd.user.services.dms.wantedBy == [ "mango-session.target" ];
    "dms user service skips the greeter" =
      cfg.systemd.user.services.dms.unitConfig.ConditionUser == "!@system";
    # The session bring-up must be a single script: mango spawns each exec_once
    # asynchronously, so splitting the environment export from the target start
    # would race and hand the portal (and the shell) an empty environment.
    "session setup autostarted" = lib.hasInfix "-itera-mango-session-setup" bobMango;
    "session setup starts mango-session.target" =
      lib.hasInfix "systemctl --user start mango-session.target" (builtins.readFile bobSessionSetup);
    "session setup exports the environment first" =
      lib.hasInfix "dbus-update-activation-environment --all" (builtins.readFile bobSessionSetup);

    # ── mango keybinds: per-user override ────────────────────────────────
    "per-user keybind override rendered (alice)" =
      lib.hasInfix "binds=SUPER,Return,spawn,foot" aliceMango;

    # ── mango layout: default reaches bob, per-user override wins for alice ──
    "default layout rendered on tag 1 (bob)" =
      lib.hasInfix "tag_rule=id:1,layout_name:scroller" bobMango;
    "default layout rendered on tag 9 (bob)" =
      lib.hasInfix "tag_rule=id:9,layout_name:scroller" bobMango;
    # Empty default cycle: no circle_layout line, so switch_layout reaches every layout.
    "no circle_layout by default (bob)" = !(lib.hasInfix "circle_layout=" bobMango);
    "per-user layout override wins (alice)" = lib.hasInfix "tag_rule=id:1,layout_name:tile" aliceMango;
    "scroller centers focus by default (bob)" = lib.hasInfix "\nscroller_focus_center=1" bobMango;
    "per-user scroller centering opt-out (alice)" =
      lib.hasInfix "\nscroller_focus_center=0" aliceMango
      && !(lib.hasInfix "scroller_focus_center=1" aliceMango);
    "switch-layout bind rendered (SUPER+SHIFT+n)" =
      lib.hasInfix "binds=SUPER+SHIFT,n,switch_layout," bobMango;
    # Move-to-monitor needs SUPER; bare CTRL+SHIFT+j/k would steal app shortcuts.
    "move-to-monitor bind uses SUPER" = lib.hasInfix "binds=SUPER+CTRL+SHIFT,h,tagmon,left,1" bobMango;
    "no bare CTRL+SHIFT bind" = !(lib.hasInfix "binds=CTRL+SHIFT," bobMango);
    "focus-monitor bind rendered" = lib.hasInfix "binds=SUPER+CTRL,l,focusmon,right" bobMango;
    "fullscreen bind rendered" = lib.hasInfix "binds=SUPER+SHIFT,f,togglefullscreen," bobMango;
    # SHIFT+Tab emits ISO_Left_Tab, so the reverse switcher must be a keycode bind.
    "reverse switcher is a keycode bind" = lib.hasInfix "bind=ALT+SHIFT,Tab,switcher,prev" bobMango;
    # DMS theme fragments are sourced (optional), but never its binds.
    "dms colors fragment sourced" = lib.hasInfix "source_optional=./dms/colors.conf" bobMango;
    "dms binds fragment not sourced" = !(lib.hasInfix "dms/binds.conf" bobMango);
    # Directional focus crosses monitors at the edge, but never tags.
    "focus crosses monitors" = lib.hasInfix "focus_cross_monitor=1" bobMango;
    "focus does not cross tags" = !(lib.hasInfix "focus_cross_tag=1" bobMango);
    "default mouse move bind rendered" =
      lib.hasInfix "mousebind=SUPER,btn_left,moveresize,curmove" bobMango;
    "user bind on a default's key replaces it (alice)" =
      lib.hasInfix "binds=SHIFT+SUPER,f,spawn,firefox" aliceMango
      && !(lib.hasInfix "togglefullscreen" aliceMango);
    "default on that key kept for others (bob)" = lib.hasInfix "togglefullscreen" bobMango;
    "mouse-bind defaults opt-out (alice)" = !(lib.hasInfix "mousebind=" aliceMango);
    "full-width bind rendered" = lib.hasInfix "binds=SUPER+CTRL,r,set_proportion,1.0" bobMango;
    # DMS notifications keeps SUPER+n — no collision with the layout bind.
    "dms notifications keeps SUPER+n" = lib.hasInfix "binds=SUPER,n,spawn_shell," bobMango;

    # ── mango monitors: system-wide default reaches every user ───────────
    # bob inherits both system rules; the key→name default renders the anchored `name:^HDMI-1$`.
    "monitor default reaches user (bob HDMI-1)" =
      lib.hasInfix "monitor_rule=name:^HDMI-1$,width:1920,height:1080,refresh:60,x:0,y:0" bobMango;
    "monitor default reaches user (bob DP-2)" =
      lib.hasInfix "monitor_rule=name:^DP-2$,width:2560,height:1440,refresh:60,x:1920,y:0" bobMango;

    # ── mango monitors: per-user override wins per KEY, sibling still inherits ──
    "per-user monitor override wins (alice HDMI-1)" =
      lib.hasInfix "monitor_rule=name:^HDMI-1$,width:3840,height:2160,refresh:120,x:0,y:0,scale:1.5,rr:3" aliceMango;
    "per-user override replaces the system rule (alice)" =
      !(lib.hasInfix "monitor_rule=name:^HDMI-1$,width:1920" aliceMango);
    "sibling monitor still inherited (alice DP-2)" =
      lib.hasInfix "monitor_rule=name:^DP-2$,width:2560,height:1440,refresh:60,x:1920,y:0" aliceMango;
    # Fractional scale is stripped (proves fmtNum) — must NOT be scale:1.500000.
    "monitor scale rendered stripped (alice)" = lib.hasInfix "scale:1.5," aliceMango;

    # ── greeter: system settings unless a user is synced ─────────────────
    "greeter syncs no user by default" = cfg.programs.dms-greeter.configHome == null;
    "greetd merges the greeter settings" =
      lib.hasInfix "-itera-dms-greeter-settings.json" cfg.systemd.services.greetd.preStart;
    "greeter gets the system itera settings" =
      greeterSettings.currentThemeName == "blue" && !(greeterSettings ? radiusStrength);
    "greeter shows the greeter image by default" =
      lib.hasInfix "itera-greeter" greeterSettings.lockScreenWallpaperPath;
    "greeter wallpaper option sets only the greeter's copy" =
      greeterWallpaperSettings.lockScreenWallpaperPath == "/etc/login-wallpaper.jpg";

    # ── mango monitors: the login greeter gets the system-wide layout ────
    "greeter gets system-wide monitors (HDMI-1)" =
      lib.hasInfix "monitor_rule=name:^HDMI-1$,width:1920,height:1080,refresh:60,x:0,y:0" greeterMonitors;
    "greeter gets system-wide monitors (DP-2)" =
      lib.hasInfix "monitor_rule=name:^DP-2$,width:2560,height:1440,refresh:60,x:1920,y:0" greeterMonitors;

    # ── mango gestures: system default reaches every user, per-user adds ──
    "gesture default reaches user (bob)" =
      lib.hasInfix "gesturebind=none,left,3,focusdir,right" bobMango;
    "gesture default reaches user (alice)" =
      lib.hasInfix "gesturebind=none,left,3,focusdir,right" aliceMango;
    "per-user gesture added (alice)" = lib.hasInfix "gesturebind=SUPER,up,4,switch_layout," aliceMango;
    "per-user gesture not leaked to other user (bob)" =
      !(lib.hasInfix "gesturebind=SUPER,up,4,switch_layout" bobMango);

    # ── mango keyboard layout: system xkb reaches every session + greeter ──
    "session xkb variant reaches user (bob)" = lib.hasInfix "xkb_rules_variant=colemak_dh" bobMango;
    "session xkb variant reaches user (alice)" = lib.hasInfix "xkb_rules_variant=colemak_dh" aliceMango;
    "greeter gets system xkb variant" = lib.hasInfix "xkb_rules_variant=colemak_dh" greeterMonitors;

    # ── per-user packages escape hatch ───────────────────────────────────
    "per-user package installed (alice)" = builtins.elem "hello" (
      map lib.getName cfg.users.users.alice.packages
    );
    # (bob still gets the look's user tmpfiles rules as a package, so check by name.)
    "per-user packages stay per user (bob)" =
      !(builtins.elem "hello" (map lib.getName cfg.users.users.bob.packages));

    # ── monitor renderer unit ────────────────────────────────────────────
    "monitor renderer: anchored name preserved" = lib.hasInfix "name:^eDP-1$" renderedMonitor;
    "monitor renderer: float refresh stripped" = lib.hasInfix "refresh:59.951," renderedMonitor;
    "monitor renderer: float scale stripped" = lib.hasInfix "scale:1.5," renderedMonitor;
    "monitor renderer: transform maps to rr" = lib.hasInfix "rr:1" renderedMonitor;
    "monitor renderer: bool renders as 1" = lib.hasInfix "vrr:1" renderedMonitor;
    "monitor renderer: primary rendered" = lib.hasInfix "primary:1" renderedMonitor;
    "monitor renderer: hdr luminance rendered" = lib.hasInfix "hdr_max_lum:616" renderedMonitor;
    "monitor renderer: disabled emits disable:1" =
      lib.hasInfix "monitor_rule=name:HDMI-2,disable:1" renderedMonitor;
    "monitor renderer: disabled omits setting fields" = !(lib.hasInfix "width:9999" renderedMonitor);

    # ── renderer unit ────────────────────────────────────────────────────
    "renderer joins modifiers with +" = lib.hasInfix "binds=SUPER+SHIFT,q,quit," renderedBind;
    "renderer empty modifiers → none" =
      lib.hasInfix "binds=none,XF86AudioMute,spawn_shell,true" renderedBind;
    # DMS's cheatsheet reads a bind's label only from the comment line above it.
    "renderer puts the description on the line above the bind" =
      lib.hasInfix "# Exit mango\nbinds=SUPER+SHIFT,q,quit," renderedBind;
    # Layout renderers: per-tag tag_rule lines and the circle_layout line.
    "tag-layout renderer emits per-tag rules" = lib.hasInfix "tag_rule=id:1,layout_name:tile" (
      self.lib.mango.mkTagLayoutLines { layout = "tile"; }
    );
    "circle-layout renderer joins with comma" =
      self.lib.mango.mkCircleLayoutLine [
        "scroller"
        "tile"
      ] == "circle_layout=scroller,tile";
    "circle-layout renderer empty → omitted" = self.lib.mango.mkCircleLayoutLine [ ] == "";
  };

in
mkCheckDrv "itera-user-defaults-eval" checks
