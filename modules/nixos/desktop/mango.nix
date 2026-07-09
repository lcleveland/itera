# itera's mango compositor battery.
#
# A thin, opinionated wrapper over the mango NixOS module (bundled by
# `modules/nixos/default.nix`). mango is a dwl-based wlroots Wayland compositor;
# enabling this turns it on and — through the upstream module — brings along the
# xdg-desktop-portal wiring (wlr + gtk), polkit, xwayland, and registers a
# `mango` wayland session with the display manager.
#
# Unlike the core-boot batteries, a desktop is NOT part of the opinionated base,
# so this gates on its OWN `enable` (`mkEnableOption`, opt-in) rather than the
# global `itera.enable` — exactly like `itera.disko`. The matching user-side
# config (autostart, keybinds) lives in the hjem battery `itera.programs.mango`.
#
# This module also holds the system-wide default keybind set
# (`itera.desktop.mango.keybinds`) that every user inherits — the "default
# settings for all users" for the compositor. The hjem battery reads it via
# `osConfig`, merges per-user overrides, and renders it into config.conf.
#
# Fine-grained tuning stays reachable through the native `programs.mango.*`
# options, which remain in place because the upstream module is bundled (the same
# arrangement `itera.hardening` uses for `nix-mineral.*`).
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) attrsOf nullOr str;

  iteraLib = import ../../../lib { inherit lib; };

  cfg = config.itera.desktop.mango;

  dmsEnabled = config.itera.desktop.dankMaterialShell.enable;

  # ── Assembled default keybind set ─────────────────────────────────────────
  # Every bind uses the `s` (keysym) flag, matching the mango convention. Names
  # are organisational only (they let a user override a single default bind by
  # re-declaring the same name).
  tags = builtins.genList (i: i + 1) 9;

  # SUPER+1..9 → view tag N; SUPER+SHIFT+1..9 → move focused window to tag N.
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
          flagModifiers = [ "s" ];
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

  # Spawn binds gated on their command being configured (itera does not ship a
  # terminal / file manager, so these stay off unless the consumer names one).
  terminalBind = lib.optionalAttrs (cfg.commands.terminal != null) {
    terminal = {
      modifierKeys = [ "SUPER" ];
      flagModifiers = [ "s" ];
      keySymbol = "t";
      mangoCommand = "spawn";
      commandArguments = cfg.commands.terminal;
    };
  };

  fileBrowserBind = lib.optionalAttrs (cfg.commands.fileBrowser != null) {
    fileBrowser = {
      modifierKeys = [ "SUPER" ];
      flagModifiers = [ "s" ];
      keySymbol = "f";
      mangoCommand = "spawn";
      commandArguments = cfg.commands.fileBrowser;
    };
  };

  defaultKeybinds =
    tagBinds
    // directionalBinds
    // staticBinds
    // mediaBinds
    // dmsBinds
    // terminalBind
    // fileBrowserBind;
in
{
  options.itera.desktop.mango = {
    enable = mkEnableOption "the mango Wayland compositor";

    commands = {
      terminal = mkOption {
        type = nullOr str;
        default = null;
        example = "foot";
        description = ''
          Command SUPER+t spawns. `null` (default) means itera adds no terminal
          keybind (itera ships no terminal — name one to get the bind).
        '';
      };

      fileBrowser = mkOption {
        type = nullOr str;
        default = null;
        example = "foot -e yazi";
        description = "Command SUPER+f spawns. `null` (default) adds no file-browser keybind.";
      };
    };

    keybinds = mkOption {
      type = attrsOf iteraLib.mango.keybindType;
      default = defaultKeybinds;
      defaultText = lib.literalExpression "itera's curated default MangoWC keybind set";
      description = ''
        System-wide default MangoWC keybinds applied to every user. The hjem
        battery `itera.programs.mango` reads this via `osConfig`, merges per-user
        overrides ({option}`hjem.users.<name>.itera.programs.mango.keybinds`,
        keyed by bind name) on top, and renders the result into config.conf.

        Add or replace a single bind by declaring the same attribute name; the
        set uses camelCase names organisationally (they never reach the file).
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.mango.enable = mkDefault true;
  };
}
