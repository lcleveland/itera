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
    ;

  cfg = mkConfig [
    {
      # A system-level DMS default override (should reach every user).
      itera.desktop.dankMaterialShell.settings.currentThemeName = "blue";

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
    # Browser battery (opt-out, ON by default) wires SUPER+b to launch librewolf.
    "browser keybind launches librewolf" = lib.hasInfix "binds=SUPER,b,spawn,librewolf" mangoConfigText;
    "per-user keybind override rendered" = lib.hasInfix "binds=SUPER,Return,spawn,foot" mangoConfigText;
    "autostart still present" = lib.hasInfix "exec-once=dms run" mangoConfigText;

    # ── mango layout ─────────────────────────────────────────────────────
    # Default tiling layout is scroller, applied to every tag (id:1..9).
    "default layout rendered on tag 1" =
      lib.hasInfix "tagrule=id:1,layout_name:scroller" mangoConfigText;
    "default layout rendered on tag 9" =
      lib.hasInfix "tagrule=id:9,layout_name:scroller" mangoConfigText;
    "circle_layout cycle rendered" =
      lib.hasInfix "circle_layout=scroller,tile,monocle,grid" mangoConfigText;
    "switch-layout bind rendered (SUPER+SHIFT+n)" =
      lib.hasInfix "binds=SUPER+SHIFT,n,switch_layout," mangoConfigText;
    # DMS notifications keeps SUPER+n — no collision with the layout bind.
    "dms notifications keeps SUPER+n" = lib.hasInfix "binds=SUPER,n,spawn_shell," mangoConfigText;

    # ── renderer unit ────────────────────────────────────────────────────
    "renderer joins modifiers with +" = lib.hasInfix "binds=SUPER+SHIFT,q,quit," renderedBind;
    "renderer empty modifiers → none" =
      lib.hasInfix "binds=none,XF86AudioMute,spawn_shell,true" renderedBind;
    # Layout renderers: per-tag tagrule lines and the circle_layout line.
    "tag-layout renderer emits per-tag rules" = lib.hasInfix "tagrule=id:1,layout_name:tile" (
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
