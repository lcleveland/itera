# Curated-program registration for mango (MangoWC).
#
# Declares mango's curated options ONCE and exposes them at two levels:
#   - `itera.programs.mango.*`               — system-wide default for every user
#   - `itera.users.<name>.programs.mango.*`  — per-user override (wins per key)
#
# The assembled default keybind set lives here (it is a function of the
# host-level spawn commands in `itera.desktop.mango.commands` and whether DMS is
# installed). The hjem battery `modules/hjem/programs/mango.nix` reads the merged
# result via `osConfig` and renders it into `~/.config/mango/config.conf`.
#
# See lib/programs.nix for the framework. This file is NOT a NixOS module — it is
# a registration record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkDefault;
  inherit (lib.types)
    attrsOf
    enum
    listOf
    bool
    lines
    ;
  inherit (iteraLib.mango) monitorRuleType;
in
iteraLib.programs.mkCuratedProgram {
  name = "mango";

  fields = {
    keybinds = {
      type = attrsOf iteraLib.mango.keybindType;
      attrs = true;
      description = ''
        MangoWC keybinds, name-keyed. At the system-wide level
        ({option}`itera.programs.mango.keybinds`) this is itera's curated default
        set; per-user ({option}`itera.users.<name>.programs.mango.keybinds`) a bind
        replaces any default with the same attribute name OR on the same key
        combination (so rebinding SUPER+t needs no knowledge of the default's
        name); other binds are added. The names never reach the file.
      '';
      example = lib.literalExpression ''
        {
          terminal = {
            modifierKeys = [ "SUPER" ];
            keySymbol = "Return";
            mangoCommand = "spawn";
            commandArguments = "foot";
          };
        }
      '';
    };

    mousebinds = {
      type = attrsOf iteraLib.mango.mouseBindType;
      attrs = true;
      description = ''
        MangoWC mouse button binds, name-keyed, rendered as `mousebind=` lines.
        Merges like `gestures`: the system-wide level
        ({option}`itera.programs.mango.mousebinds`) is the default set
        (SUPER+left-drag moves a window, SUPER+right-drag resizes it); per-user
        ({option}`itera.users.<name>.programs.mango.mousebinds`) a bind whose
        attribute name matches replaces it, new names are added.
      '';
      example = lib.literalExpression ''
        {
          closeOnMiddle = {
            modifierKeys = [ "SUPER" ];
            button = "btn_middle";
            mangoCommand = "killclient";
          };
        }
      '';
    };

    gestures = {
      type = attrsOf iteraLib.mango.gestureType;
      attrs = true;
      description = ''
        MangoWC touchpad gestures, name-keyed, rendered as `gesturebind=` lines.
        Merges like `keybinds`: the system-wide level
        ({option}`itera.programs.mango.gestures`) is the default set; per-user
        ({option}`itera.users.<name>.programs.mango.gestures`) a gesture whose
        attribute name matches replaces it, new names are added. Defaults to
        mango's own set: 3-finger swipes move focus, 4-finger left/right switch to
        the next/previous occupied tag, 4-finger up/down enter/leave overview.
      '';
      example = lib.literalExpression ''
        {
          # 3-finger swipe left focuses the window to the right.
          focusRight = {
            direction = "left";
            fingerCount = 3;
            mangoCommand = "focusdir";
            commandArguments = "right";
          };
        }
      '';
    };

    layout = {
      type = enum iteraLib.mango.supportedLayouts;
      default = "scroller";
      example = "tile";
      description = ''
        Default tiling layout, applied to every tag via `tag_rule` lines. Defaults
        to `scroller` (a PaperWM-style scrollable strip).
      '';
    };

    layoutCycle = {
      type = listOf (enum iteraLib.mango.supportedLayouts);
      default = [ ];
      example = [
        "scroller"
        "tile"
        "monocle"
        "grid"
      ];
      description = ''
        Layouts the SUPER+SHIFT+n `switch_layout` bind cycles through (rendered as
        MangoWC's `circle_layout`). Empty (the default) omits the line, so the bind
        cycles every built-in layout; list a subset to restrict it.
      '';
    };

    scrollerFocusCenter = {
      type = bool;
      default = true;
      example = false;
      description = ''
        Center the focused column in the scroller layout (MangoWC's
        `scroller_focus_center`). mango only re-centers when the strip has to
        scroll, so a column that is already fully on screen keeps its place.
        Set `false` for mango's default edge-aligned scrolling.
      '';
    };

    monitors = {
      type = attrsOf monitorRuleType;
      attrs = true;
      description = ''
        MangoWC output configuration (position, resolution, scale, refresh,
        rotation, VRR/HDR, enable), rendered as `monitor_rule=` lines in
        {file}`mango/config.conf`. Keyed by a friendly name that defaults into the
        `name` match as an exact, anchored regex (`^eDP-1$`), so keying by
        connector name (e.g. `"eDP-1"`) is usually enough. mango applies only the
        first rule matching an output.

        At the system-wide level ({option}`itera.programs.mango.monitors`) this is
        the default for every user (and also feeds the login greeter); per-user
        ({option}`itera.users.<name>.programs.mango.monitors`) a monitor whose
        attribute name matches a default replaces it wholesale, and new names are
        added.

        Empty by default, which lets mango auto-configure every output.
      '';
      example = lib.literalExpression ''
        {
          # Laptop panel at the origin, 1.5x scale.
          "eDP-1" = {
            width = 1920;
            height = 1080;
            refresh = 60;
            x = 0;
            y = 0;
            scale = 1.5;
          };
          # Any HDMI display to the right, rotated 90°, matched by a custom regex.
          external = {
            name = "^HDMI-A-.*$";
            x = 1920;
            y = 0;
            transform = "90";
          };
        }
      '';
    };
  };

  # Per-user-only knobs (no system-wide counterpart); the renderer reads them off
  # the per-user value with sensible fallbacks for plain (non-`itera.users`) users.
  userExtra = {
    autostart = mkOption {
      type = bool;
      default = true;
      description = ''
        Inject itera's default `exec_once` autostart into {file}`mango/config.conf`:
        refresh the D-Bus/systemd user environment and launch DankMaterialShell
        (`dms run`). Turn off to manage startup yourself via `extraConfig`.
      '';
    };

    defaultKeybinds.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Include the system-wide default keybinds
        ({option}`itera.programs.mango.keybinds`). Set `false` to start from an
        empty set and define all binds via this user's `keybinds`.
      '';
    };

    defaultMousebinds.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Include the system-wide default mouse binds
        ({option}`itera.programs.mango.mousebinds`). Set `false` to start from an
        empty set and define all mouse binds via this user's `mousebinds`.
      '';
    };

    defaultGestures.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Include the system-wide default touchpad gestures
        ({option}`itera.programs.mango.gestures`). Set `false` to start from an
        empty set and define all gestures via this user's `gestures`.
      '';
    };

    extraConfig = mkOption {
      type = lines;
      default = "";
      example = ''
        # SUPER+Return opens a terminal
        bind=SUPER,Return,spawn,foot
      '';
      description = ''
        Extra lines appended verbatim to {file}`$XDG_CONFIG_HOME/mango/config.conf`
        (keybinds, window rules, `env=` lines, further `exec_once=`, …).
      '';
    };
  };

  # The system-wide default keybind set. A function of the host spawn commands
  # (`itera.desktop.mango.commands`) and whether DMS is installed. Wrapped in
  # mkDefault so a consumer can replace it wholesale at `itera.programs.mango.keybinds`.
  systemConfig =
    config:
    let
      cfg = config.itera.desktop.mango;
      dmsEnabled = config.itera.desktop.dankMaterialShell.enable;

      # SUPER+1..9 → view tag N; SUPER+SHIFT+1..9 → move focused window to tag N.
      tags = builtins.genList (i: i + 1) 9;
      tagBinds = builtins.listToAttrs (
        lib.concatMap (tag: [
          {
            name = "viewTag${toString tag}";
            value = {
              modifierKeys = [ "SUPER" ];
              flagModifiers = [ "s" ];
              keySymbol = toString tag;
              mangoCommand = "view";
              commandArguments = toString tag;
            };
          }
          {
            name = "moveToTag${toString tag}";
            value = {
              modifierKeys = [
                "SUPER"
                "SHIFT"
              ];
              # Keycode match (no `s`): SHIFT+digit emits a punctuation keysym
              # (`1`→`exclam` on US), so a keysym bind for `1` would never fire.
              flagModifiers = [ ];
              keySymbol = toString tag;
              mangoCommand = "tag";
              commandArguments = toString tag;
            };
          }
        ]) tags
      );

      directions = [
        "left"
        "right"
        "up"
        "down"
      ];

      # Directional focus / swap / move-to-monitor on h/j/k/l.
      directionalBinds = builtins.listToAttrs (
        lib.concatMap (
          dir:
          let
            key =
              {
                left = "h";
                right = "l";
                up = "k";
                down = "j";
              }
              .${dir};
          in
          [
            {
              name = "focus${dir}";
              value = {
                modifierKeys = [ "SUPER" ];
                flagModifiers = [ "s" ];
                keySymbol = key;
                mangoCommand = "focusdir";
                commandArguments = dir;
              };
            }
            {
              name = "swap${dir}";
              value = {
                modifierKeys = [
                  "SUPER"
                  "SHIFT"
                ];
                flagModifiers = [ "s" ];
                keySymbol = key;
                mangoCommand = "exchange_client";
                commandArguments = dir;
              };
            }
            {
              name = "focusMonitor${dir}";
              value = {
                modifierKeys = [
                  "SUPER"
                  "CTRL"
                ];
                flagModifiers = [ "s" ];
                keySymbol = key;
                mangoCommand = "focusmon";
                commandArguments = dir;
              };
            }
            # Needs SUPER: a bare CTRL+SHIFT+j/k would swallow app shortcuts
            # (browser devtools consoles, terminal copy/paste variants).
            {
              name = "moveMonitor${dir}";
              value = {
                modifierKeys = [
                  "SUPER"
                  "CTRL"
                  "SHIFT"
                ];
                flagModifiers = [ "s" ];
                keySymbol = key;
                mangoCommand = "tagmon";
                commandArguments = "${dir},1";
              };
            }
            # Scroller: pull the window into / push it out of the neighbouring
            # column's stack.
            {
              name = "scrollerStack${dir}";
              value = {
                modifierKeys = [
                  "SUPER"
                  "ALT"
                ];
                flagModifiers = [ "s" ];
                keySymbol = key;
                mangoCommand = "scroller_stack";
                commandArguments = dir;
              };
            }
          ]
        ) directions
      );

      staticBinds = {
        closeWindow = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "q";
          mangoCommand = "killclient";
        };
        quit = {
          modifierKeys = [
            "SUPER"
            "SHIFT"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "q";
          mangoCommand = "quit";
        };
        toggleFloat = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "g";
          mangoCommand = "togglefloating";
        };
        toggleFullscreen = {
          modifierKeys = [
            "SUPER"
            "SHIFT"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "f";
          mangoCommand = "togglefullscreen";
        };
        toggleMaximize = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "m";
          mangoCommand = "togglemaximizescreen";
        };
        toggleOverview = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "Tab";
          mangoCommand = "toggleoverview";
        };
        # Thumbnail window switcher; releasing ALT selects. The SHIFT variant is a
        # keycode bind (no `s`): SHIFT+Tab emits `ISO_Left_Tab`, not `Tab`.
        switcherNext = {
          modifierKeys = [ "ALT" ];
          flagModifiers = [ "s" ];
          keySymbol = "Tab";
          mangoCommand = "switcher";
          commandArguments = "next";
        };
        switcherPrev = {
          modifierKeys = [
            "ALT"
            "SHIFT"
          ];
          keySymbol = "Tab";
          mangoCommand = "switcher";
          commandArguments = "prev";
        };
        previousTag = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "grave";
          mangoCommand = "view";
          commandArguments = "-1";
        };
        # Scroller: cycle the focused column through `scroller_proportion_preset`.
        # Scroller: make the focused column full width.
        fullWidth = {
          modifierKeys = [
            "SUPER"
            "CTRL"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "r";
          mangoCommand = "set_proportion";
          commandArguments = "1.0";
        };
        cycleProportion = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "r";
          mangoCommand = "switch_proportion_preset";
        };
        scratchpad = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "s";
          mangoCommand = "toggle_scratchpad";
        };
        minimize = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "i";
          mangoCommand = "minimized";
        };
        restoreMinimized = {
          modifierKeys = [
            "SUPER"
            "SHIFT"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "i";
          mangoCommand = "restore_minimized";
        };
        reloadConfig = {
          modifierKeys = [
            "SUPER"
            "SHIFT"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "r";
          mangoCommand = "reload_config";
        };
        # Cycle the current tag's tiling layout through `layoutCycle` (rendered as
        # `circle_layout`). SHIFT variant so it clears SUPER+n (DMS notifications).
        cycleLayout = {
          modifierKeys = [
            "SUPER"
            "SHIFT"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "n";
          mangoCommand = "switch_layout";
        };
      };

      # Media/volume/brightness keys. With DMS they go through its IPC, which
      # shows the OSD and drives external monitors over DDC as well as the
      # backlight; without it they fall back to wpctl/playerctl/brightnessctl.
      # `l` keeps them working on the lock screen.
      #
      # Fallback volume goes through wpctl (WirePlumber), NOT pactl. `pactl`
      # ships in `pkgs.pulseaudio`, which a PipeWire system never installs — the
      # PipeWire module only puts `pkgs.pipewire` (the `pw-*` tools) on PATH, so
      # a `pactl` bind is a silent no-op. `wpctl` is always there: the
      # WirePlumber module installs its own package and defaults to on whenever
      # PipeWire is, which is exactly where these binds live. `-l 1.0` caps the
      # raise at 100% so holding the key cannot push the sink into software
      # boost and clip.
      mediaBind = modifierKeys: keySymbol: dmsCall: fallback: {
        inherit modifierKeys keySymbol;
        flagModifiers = [
          "s"
          "l"
        ];
        mangoCommand = "spawn_shell";
        commandArguments = if dmsEnabled then "dms ipc call ${dmsCall}" else fallback;
      };
      mediaBinds = {
        volumeUp =
          mediaBind [ ] "XF86AudioRaiseVolume" "audio increment 5"
            "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
        volumeDown =
          mediaBind [ ] "XF86AudioLowerVolume" "audio decrement 5"
            "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        volumeMute =
          mediaBind [ ] "XF86AudioMute" "audio mute"
            "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        micMute =
          mediaBind [ ] "XF86AudioMicMute" "audio micmute"
            "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
        mediaPlay = mediaBind [ ] "XF86AudioPlay" "mpris playPause" "playerctl play-pause";
        mediaPause = mediaBind [ ] "XF86AudioPause" "mpris playPause" "playerctl play-pause";
        mediaNext = mediaBind [ ] "XF86AudioNext" "mpris next" "playerctl next";
        mediaPrev = mediaBind [ ] "XF86AudioPrev" "mpris previous" "playerctl previous";
        # `""` = every brightness device DMS knows (backlight and DDC monitors).
        brightnessUp =
          mediaBind [ ] "XF86MonBrightnessUp" ''brightness increment 10 ""''
            "brightnessctl set +10%";
        brightnessDown =
          mediaBind [ ] "XF86MonBrightnessDown" ''brightness decrement 10 ""''
            "brightnessctl set 10%-";
      }
      # CTRL+volume sets the player's own volume; DMS-only.
      // lib.optionalAttrs dmsEnabled {
        playerVolumeUp = mediaBind [ "CTRL" ] "XF86AudioRaiseVolume" "mpris increment 5" null;
        playerVolumeDown = mediaBind [ "CTRL" ] "XF86AudioLowerVolume" "mpris decrement 5" null;
      };

      # DMS ipc actions — only meaningful when the shell is installed.
      dmsBind = modifierKeys: keySymbol: commandArguments: {
        inherit modifierKeys keySymbol commandArguments;
        flagModifiers = [ "s" ];
        mangoCommand = "spawn_shell";
      };
      dmsBinds = lib.optionalAttrs dmsEnabled {
        spotlight = dmsBind [ "SUPER" ] "d" "dms ipc call spotlight toggle";
        lockScreen = dmsBind [ "SUPER" ] "Escape" "dms ipc call lock lock";
        notifications = dmsBind [ "SUPER" ] "n" "dms ipc call notifications toggle";
        # Pick the tag's layout by name (the layoutChooser launcher plugin).
        chooseLayout = dmsBind [
          "SUPER"
          "CTRL"
        ] "n" "dms ipc call spotlight openQuery '#layout '";
        clipboard = dmsBind [ "SUPER" ] "v" "dms ipc call clipboard toggle";
        settings = dmsBind [ "SUPER" ] "comma" "dms ipc call settings focusOrToggle";
        powerMenu = dmsBind [ "SUPER" ] "x" "dms ipc call powermenu toggle";
        controlCenter = dmsBind [ "SUPER" ] "a" "dms ipc call control-center toggle";
        wallpapers = dmsBind [ "SUPER" ] "y" "dms ipc call dash toggle wallpaper";
        displayProfile = dmsBind [ "SUPER" ] "p" "dms ipc outputs cycleProfile";
        colorPicker = dmsBind [
          "SUPER"
          "SHIFT"
        ] "c" "dms ipc call color-picker toggle";
        windowRule = dmsBind [
          "SUPER"
          "SHIFT"
        ] "w" "dms ipc call window-rules toggle";
        nightMode = dmsBind [
          "SUPER"
          "ALT"
        ] "n" "dms ipc call night toggle";
        idleInhibit = dmsBind [
          "SUPER"
          "ALT"
        ] "i" "dms ipc call inhibit toggle";
        processList = dmsBind [
          "CTRL"
          "ALT"
        ] "Delete" "dms ipc call processlist focusOrToggle";
        # Keycode match (no `s`): SHIFT+slash emits `question`, so a keysym bind
        # for `slash` would never fire.
        cheatsheet =
          dmsBind [
            "SUPER"
            "SHIFT"
          ] "slash" "dms ipc call keybinds toggle mangowc"
          // {
            flagModifiers = [ ];
          };
        screenshot = dmsBind [
          "SUPER"
          "SHIFT"
        ] "s" "dms screenshot --no-file";
        screenshotArea = dmsBind [ ] "Print" "dms screenshot";
        screenshotFull = dmsBind [ "CTRL" ] "Print" "dms screenshot full";
        screenshotWindow = dmsBind [ "ALT" ] "Print" "dms screenshot window";
      };

      # Spawn binds gated on their command being configured.
      spawnBind =
        cmd: key:
        lib.optionalAttrs (cmd != null) {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = key;
          mangoCommand = "spawn";
          commandArguments = cmd;
        };
      terminalBind = lib.optionalAttrs (cfg.commands.terminal != null) {
        terminal = spawnBind cfg.commands.terminal "t";
      };
      fileBrowserBind = lib.optionalAttrs (cfg.commands.fileBrowser != null) {
        fileBrowser = spawnBind cfg.commands.fileBrowser "f";
      };
      browserBind = lib.optionalAttrs (cfg.commands.browser != null) {
        browser = spawnBind cfg.commands.browser "b";
      };
      editorBind = lib.optionalAttrs (cfg.commands.editor != null) {
        editor = spawnBind cfg.commands.editor "e";
      };
      # Two binds for one command: SUPER+c matches the other app binds, and
      # `XF86Calculator` is the dedicated calculator key most keyboards ship —
      # a dead key until something claims it, like the media keys above. That one
      # takes NO modifier (`modifierKeys = [ ]`, rendered as `none`), same as the
      # media/brightness binds, so pressing the key by itself fires it.
      calculatorBind = lib.optionalAttrs (cfg.commands.calculator != null) {
        calculator = spawnBind cfg.commands.calculator "c";
        calculatorKey = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86Calculator";
          mangoCommand = "spawn";
          commandArguments = cfg.commands.calculator;
        };
      };
      # Labels for DMS's keybind cheatsheet (SUPER+SHIFT+/), keyed by bind name.
      descriptions =
        lib.listToAttrs (
          lib.concatMap (tag: [
            (lib.nameValuePair "viewTag${toString tag}" "View tag ${toString tag}")
            (lib.nameValuePair "moveToTag${toString tag}" "Move window to tag ${toString tag}")
          ]) tags
        )
        // lib.listToAttrs (
          lib.concatMap (dir: [
            (lib.nameValuePair "focus${dir}" "Focus ${dir}")
            (lib.nameValuePair "swap${dir}" "Swap window ${dir}")
            (lib.nameValuePair "focusMonitor${dir}" "Focus monitor ${dir}")
            (lib.nameValuePair "moveMonitor${dir}" "Move window to monitor ${dir}")
            (lib.nameValuePair "scrollerStack${dir}" "Stack window ${dir}")
          ]) directions
        )
        // {
          closeWindow = "Close window";
          quit = "Exit mango";
          toggleFloat = "Toggle floating";
          toggleFullscreen = "Toggle fullscreen";
          toggleMaximize = "Toggle maximize";
          toggleOverview = "Overview";
          switcherNext = "Window switcher";
          switcherPrev = "Window switcher (reverse)";
          previousTag = "Previous tag";
          fullWidth = "Full-width column";
          cycleProportion = "Cycle column width";
          scratchpad = "Toggle scratchpad";
          minimize = "Minimize window";
          restoreMinimized = "Restore minimized window";
          reloadConfig = "Reload mango config";
          cycleLayout = "Cycle layout";
          volumeUp = "Volume up";
          volumeDown = "Volume down";
          volumeMute = "Mute";
          micMute = "Mute microphone";
          mediaPlay = "Play/pause";
          mediaPause = "Play/pause";
          mediaNext = "Next track";
          mediaPrev = "Previous track";
          brightnessUp = "Brightness up";
          brightnessDown = "Brightness down";
          playerVolumeUp = "Player volume up";
          playerVolumeDown = "Player volume down";
          spotlight = "Application launcher";
          lockScreen = "Lock screen";
          notifications = "Notification center";
          chooseLayout = "Choose layout";
          clipboard = "Clipboard history";
          settings = "Settings";
          powerMenu = "Power menu";
          controlCenter = "Control center";
          wallpapers = "Browse wallpapers";
          displayProfile = "Cycle display profile";
          colorPicker = "Color picker";
          windowRule = "Create window rule";
          nightMode = "Night mode";
          idleInhibit = "Idle inhibit";
          processList = "Task manager";
          cheatsheet = "Keyboard shortcuts";
          screenshot = "Screenshot to clipboard";
          screenshotArea = "Screenshot: area";
          screenshotFull = "Screenshot: full screen";
          screenshotWindow = "Screenshot: window";
          terminal = "Terminal";
          fileBrowser = "File browser";
          browser = "Web browser";
          editor = "Editor";
          calculator = "Calculator";
          calculatorKey = "Calculator";
        };
    in
    {
      mousebinds = mkDefault {
        moveWindow = {
          modifierKeys = [ "SUPER" ];
          button = "btn_left";
          mangoCommand = "moveresize";
          commandArguments = "curmove";
        };
        resizeWindow = {
          modifierKeys = [ "SUPER" ];
          button = "btn_right";
          mangoCommand = "moveresize";
          commandArguments = "curresize";
        };
      };

      # mango's own default gesture set (assets/config.conf upstream).
      gestures = mkDefault (
        lib.genAttrs' [ "left" "right" "up" "down" ] (dir: {
          name = "focus${dir}";
          value = {
            direction = dir;
            mangoCommand = "focusdir";
            commandArguments = dir;
          };
        })
        // {
          nextTag = {
            direction = "left";
            fingerCount = 4;
            mangoCommand = "viewnext_have_client";
          };
          previousTag = {
            direction = "right";
            fingerCount = 4;
            mangoCommand = "viewprev_have_client";
          };
          enterOverview = {
            direction = "up";
            fingerCount = 4;
            mangoCommand = "enteroverview";
          };
          leaveOverview = {
            direction = "down";
            fingerCount = 4;
            mangoCommand = "leaveoverview";
          };
        }
      );

      keybinds = mkDefault (
        lib.mapAttrs (name: bind: { description = descriptions.${name} or null; } // bind) (
          tagBinds
          // directionalBinds
          // staticBinds
          // mediaBinds
          // dmsBinds
          // terminalBind
          // fileBrowserBind
          // browserBind
          // editorBind
          // calculatorBind
        )
      );
    };
}
