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
        whose attribute name matches a default replaces it, new names are added.
        The names are organisational only — they never reach the file.
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

    gestures = {
      type = attrsOf iteraLib.mango.gestureType;
      attrs = true;
      description = ''
        MangoWC touchpad gestures, name-keyed, rendered as `gesturebind=` lines.
        Merges like `keybinds`: the system-wide level
        ({option}`itera.programs.mango.gestures`) is the default set; per-user
        ({option}`itera.users.<name>.programs.mango.gestures`) a gesture whose
        attribute name matches replaces it, new names are added. Empty by default.
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
        Default tiling layout, applied to every tag via `tagrule` lines. Defaults
        to `scroller` (a PaperWM-style scrollable strip).
      '';
    };

    layoutCycle = {
      type = listOf (enum iteraLib.mango.supportedLayouts);
      default = [
        "scroller"
        "tile"
        "monocle"
        "grid"
      ];
      description = ''
        Layouts the SUPER+SHIFT+n `switch_layout` bind cycles through (rendered as
        MangoWC's `circle_layout`). An empty list omits the line and cycles every
        built-in layout instead.
      '';
    };

    monitors = {
      type = attrsOf monitorRuleType;
      attrs = true;
      description = ''
        MangoWC output configuration (position, resolution, scale, refresh,
        rotation, VRR/HDR, enable), rendered as `monitorrule=` lines in
        {file}`mango/config.conf`. Keyed by a friendly name that defaults into the
        `name` match regex, so keying by connector name (e.g. `"eDP-1"`) is usually
        enough.

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
          # External display to the right, rotated 90°, matched by an exact regex.
          external = {
            name = "^DP-1$";
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
        Inject itera's default `exec-once` autostart into {file}`mango/config.conf`:
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

    extraConfig = mkOption {
      type = lines;
      default = "";
      example = ''
        # SUPER+Return opens a terminal
        bind=SUPER,Return,spawn,foot
      '';
      description = ''
        Extra lines appended verbatim to {file}`$XDG_CONFIG_HOME/mango/config.conf`
        (keybinds, window rules, `env=` lines, further `exec-once=`, …).
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

      # Directional focus / swap / move-to-monitor on h/j/k/l.
      directionalBinds = builtins.listToAttrs (
        lib.concatMap
          (
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
                name = "moveMonitor${dir}";
                value = {
                  modifierKeys = [
                    "CTRL"
                    "SHIFT"
                  ];
                  flagModifiers = [ "s" ];
                  keySymbol = key;
                  mangoCommand = "tagmon";
                  commandArguments = "${dir},1";
                };
              }
            ]
          )
          [
            "left"
            "right"
            "up"
            "down"
          ]
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

      mediaBinds = {
        volumeUp = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86AudioRaiseVolume";
          mangoCommand = "spawn_shell";
          commandArguments = "pactl set-sink-volume @DEFAULT_SINK@ +5%";
        };
        volumeDown = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86AudioLowerVolume";
          mangoCommand = "spawn_shell";
          commandArguments = "pactl set-sink-volume @DEFAULT_SINK@ -5%";
        };
        volumeMute = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86AudioMute";
          mangoCommand = "spawn_shell";
          commandArguments = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
        };
        mediaPlay = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86AudioPlay";
          mangoCommand = "spawn_shell";
          commandArguments = "playerctl play-pause";
        };
        mediaNext = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86AudioNext";
          mangoCommand = "spawn_shell";
          commandArguments = "playerctl next";
        };
        mediaPrev = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86AudioPrev";
          mangoCommand = "spawn_shell";
          commandArguments = "playerctl previous";
        };
        brightnessUp = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86MonBrightnessUp";
          mangoCommand = "spawn_shell";
          commandArguments = "brightnessctl set +10%";
        };
        brightnessDown = {
          flagModifiers = [ "s" ];
          keySymbol = "XF86MonBrightnessDown";
          mangoCommand = "spawn_shell";
          commandArguments = "brightnessctl set 10%-";
        };
      };

      # DMS ipc actions — only meaningful when the shell is installed.
      dmsBinds = lib.optionalAttrs dmsEnabled {
        spotlight = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "d";
          mangoCommand = "spawn_shell";
          commandArguments = "dms ipc call spotlight toggle";
        };
        lockScreen = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "Escape";
          mangoCommand = "spawn_shell";
          commandArguments = "dms ipc call lock lock";
        };
        notifications = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "n";
          mangoCommand = "spawn_shell";
          commandArguments = "dms ipc call notifications toggle";
        };
        clipboard = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "v";
          mangoCommand = "spawn_shell";
          commandArguments = "dms ipc call clipboard toggle";
        };
        settings = {
          modifierKeys = [ "SUPER" ];
          flagModifiers = [ "s" ];
          keySymbol = "comma";
          mangoCommand = "spawn_shell";
          commandArguments = "dms ipc call settings toggle";
        };
        screenshot = {
          modifierKeys = [
            "SUPER"
            "SHIFT"
          ];
          flagModifiers = [ "s" ];
          keySymbol = "s";
          mangoCommand = "spawn_shell";
          commandArguments = "dms screenshot --no-file";
        };
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
    in
    {
      keybinds = mkDefault (
        tagBinds
        // directionalBinds
        // staticBinds
        // mediaBinds
        // dmsBinds
        // terminalBind
        // fileBrowserBind
        // browserBind
        // editorBind
      );
    };
}
