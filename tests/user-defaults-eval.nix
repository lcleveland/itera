# Evaluation check for itera's "default settings for all users" system:
# the `itera.users` account battery, the system-wide DankMaterialShell settings
# applied per-user, and the mango default keybinds (with per-user override).
#
# It evaluates a NixOS configuration and asserts the generated config, then also
# unit-checks the mango keybind renderer directly. `nix build` forces evaluation
# and fails loudly if any assertion is false.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  eval = nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "25.05";

        itera = {
          enable = true;
          disko.enable = false;
          impermanence.enable = false;

          # A system-level DMS default override (should reach every user).
          desktop.dankMaterialShell.settings.currentThemeName = "blue";
        };

        # Account battery: creates the account AND enables hjem.
        itera.users.alice.initialPassword = "changeme";

        # Per-user deviations from the system-wide defaults.
        hjem.users.alice.itera.programs = {
          dankMaterialShell.settings.cornerRadius = 8;
          mango.keybinds.terminal = {
            modifierKeys = [ "SUPER" ];
            keySymbol = "Return";
            mangoCommand = "spawn";
            commandArguments = "foot";
            flagModifiers = [ "s" ];
          };
        };
      }
    ];
  };
  cfg = eval.config;

  aliceFiles = cfg.hjem.users.alice.xdg.config.files;
  dmsSettings = builtins.fromJSON aliceFiles."DankMaterialShell/settings.json".text;
  mangoConfig = aliceFiles."mango/config.conf".source; # a derivation (text → writeText)
  mangoConfigText = builtins.readFile mangoConfig;

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
    };
    noMods = {
      keySymbol = "XF86AudioMute";
      mangoCommand = "spawn_shell";
      commandArguments = "true";
      flagModifiers = [ "s" ];
    };
  };

  checks = {
    # ── itera.users account battery ──────────────────────────────────────
    "itera.users creates the account" = cfg.users.users.alice.isNormalUser;
    "account has default groups" = builtins.elem "wheel" cfg.users.users.alice.extraGroups;
    "account initialPassword applied" = cfg.users.users.alice.initialPassword == "changeme";
    "hjem enabled for the user" = cfg.hjem.users.alice.enable;

    # ── DMS settings for all users ───────────────────────────────────────
    "curated system default present" = dmsSettings.configVersion == 11;
    "system-level override reaches user" = dmsSettings.currentThemeName == "blue";
    "opinionated default present" = dmsSettings.use24HourClock == true;
    "dark mode default present" = dmsSettings.syncModeWithPortal == false;
    "per-user override merges per key" = dmsSettings.cornerRadius == 8;

    # ── mango keybinds ───────────────────────────────────────────────────
    "default keybind rendered" = lib.hasInfix "binds=SUPER,q,killclient," mangoConfigText;
    # viewTag stays a keysym bind (SUPER+digit yields the digit keysym).
    "view-tag keybind rendered (keysym)" = lib.hasInfix "binds=SUPER,1,view,1" mangoConfigText;
    # moveToTag must be a keycode bind: SHIFT+digit emits a punctuation keysym,
    # so a keysym bind (`binds=`) would never fire. Guard against regressing to `s`.
    "move-to-tag keybind rendered (keycode)" = lib.hasInfix "bind=SUPER+SHIFT,1,tag,1" mangoConfigText;
    "move-to-tag is not a keysym bind" = !(lib.hasInfix "binds=SUPER+SHIFT,1,tag" mangoConfigText);
    "media keybind rendered" = lib.hasInfix "binds=none,XF86AudioMute,spawn_shell," mangoConfigText;
    "dms keybind rendered (desktop on)" = lib.hasInfix "dms ipc call spotlight toggle" mangoConfigText;
    # Browser battery (opt-out, ON by default) wires SUPER+b to launch chromium.
    "browser keybind launches chromium" = lib.hasInfix "binds=SUPER,b,spawn,chromium" mangoConfigText;
    "per-user keybind override rendered" = lib.hasInfix "binds=SUPER,Return,spawn,foot" mangoConfigText;
    "autostart still present" = lib.hasInfix "exec-once=dms run" mangoConfigText;

    # ── renderer unit ────────────────────────────────────────────────────
    "renderer joins modifiers with +" = lib.hasInfix "binds=SUPER+SHIFT,q,quit," renderedBind;
    "renderer empty modifiers → none" =
      lib.hasInfix "binds=none,XF86AudioMute,spawn_shell,true" renderedBind;
  };

  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
pkgs.runCommand "itera-user-defaults-eval" { } (
  if failed == [ ] then
    "touch $out"
  else
    throw "itera user-defaults eval check failed: ${lib.concatStringsSep "; " failed}"
)
