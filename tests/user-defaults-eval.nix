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
    ;

  cfg = mkConfig [
    {
      itera = {
        # System-wide keyboard layout (should reach every mango session + greeter).
        keyboard.variant = "colemak_dh";

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
              dankMaterialShell.settings.cornerRadius = 8;
              # Per-user Zed: register Claude Code as an external ACP agent (lands
              # under `agent_servers`) and opt the file out of clobbering so the
              # GUI can own it.
              zed = {
                clobber = false;
                settings.vim_mode = true;
                agentServers.claude = {
                  command = "claude-code-acp";
                  args = [ ];
                };
              };
              mango = {
                layout = "tile";
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

  aliceFiles = cfg.hjem.users.alice.xdg.config.files;
  bobFiles = cfg.hjem.users.bob.xdg.config.files;

  aliceDms = builtins.fromJSON aliceFiles."DankMaterialShell/settings.json".text;
  bobDms = builtins.fromJSON bobFiles."DankMaterialShell/settings.json".text;

  # Zed renders via pkgs.formats.json (a store-path `source`, not inline `text`).
  aliceZed = builtins.fromJSON (builtins.readFile aliceFiles."zed/settings.json".source);
  bobZed = builtins.fromJSON (builtins.readFile bobFiles."zed/settings.json".source);

  aliceMango = builtins.readFile aliceFiles."mango/config.conf".source;
  bobMango = builtins.readFile bobFiles."mango/config.conf".source;

  # The DMS greeter (on by default) runs its own mango instance; itera feeds it
  # the SYSTEM-WIDE monitors via `compositor.customConfig`.
  greeterMonitors = cfg.programs.dank-material-shell.greeter.compositor.customConfig;

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
    "curated system default present (bob)" = bobDms.configVersion == 11;
    "system-level override reaches user (bob)" = bobDms.currentThemeName == "blue";
    "opinionated default present (bob)" = bobDms.use24HourClock == true;
    "dark mode default present (bob)" = bobDms.syncModeWithPortal == false;

    # ── Zed settings: system defaults reach an un-overridden user (bob) ──
    "zed telemetry-off default present (bob)" = bobZed.telemetry.diagnostics == false;
    "zed raw system setting reaches user (bob)" = bobZed.buffer_font_size == 14;
    "zed curated agent field reaches user (bob)" = bobZed.agent.default_profile == "ask";
    "zed settings.json clobbers by default (bob)" = bobFiles."zed/settings.json".clobber == true;

    # ── Zed settings: per-user overrides + agents + clobber opt-out (alice) ──
    "zed per-user raw setting applied (alice)" = aliceZed.vim_mode == true;
    "zed system agent field still inherited (alice)" = aliceZed.agent.default_profile == "ask";
    "zed agentServers land under agent_servers (alice)" =
      aliceZed.agent_servers.claude.command == "claude-code-acp";
    "zed per-user clobber opt-out honored (alice)" = aliceFiles."zed/settings.json".clobber == false;

    # ── DMS settings: per-user override wins PER KEY, siblings still inherit ──
    "per-user override merges per key (alice)" = aliceDms.cornerRadius == 8;
    "sibling key still inherited (alice)" = aliceDms.use24HourClock == true;
    "system-level override still inherited (alice)" = aliceDms.currentThemeName == "blue";

    # ── mango keybinds: system defaults reach every user ─────────────────
    "default keybind rendered (alice)" = lib.hasInfix "binds=SUPER,q,killclient," aliceMango;
    "default keybind rendered (bob)" = lib.hasInfix "binds=SUPER,q,killclient," bobMango;
    # viewTag stays a keysym bind (SUPER+digit yields the digit keysym).
    "view-tag keybind rendered (keysym)" = lib.hasInfix "binds=SUPER,1,view,1" bobMango;
    # moveToTag must be a keycode bind: SHIFT+digit emits a punctuation keysym,
    # so a keysym bind (`binds=`) would never fire. Guard against regressing to `s`.
    "move-to-tag keybind rendered (keycode)" = lib.hasInfix "bind=SUPER+SHIFT,1,tag,1" bobMango;
    "move-to-tag is not a keysym bind" = !(lib.hasInfix "binds=SUPER+SHIFT,1,tag" bobMango);
    "media keybind rendered" = lib.hasInfix "binds=none,XF86AudioMute,spawn_shell," bobMango;
    "dms keybind rendered (desktop on)" = lib.hasInfix "dms ipc call spotlight toggle" bobMango;
    # Browser battery (opt-out, ON by default) wires SUPER+b to launch librewolf.
    "browser keybind launches librewolf" = lib.hasInfix "binds=SUPER,b,spawn,librewolf" bobMango;
    "autostart still present" = lib.hasInfix "exec-once=dms run" bobMango;

    # ── mango keybinds: per-user override ────────────────────────────────
    "per-user keybind override rendered (alice)" =
      lib.hasInfix "binds=SUPER,Return,spawn,foot" aliceMango;

    # ── mango layout: default reaches bob, per-user override wins for alice ──
    "default layout rendered on tag 1 (bob)" =
      lib.hasInfix "tagrule=id:1,layout_name:scroller" bobMango;
    "default layout rendered on tag 9 (bob)" =
      lib.hasInfix "tagrule=id:9,layout_name:scroller" bobMango;
    "circle_layout cycle rendered (bob)" =
      lib.hasInfix "circle_layout=scroller,tile,monocle,grid" bobMango;
    "per-user layout override wins (alice)" = lib.hasInfix "tagrule=id:1,layout_name:tile" aliceMango;
    "switch-layout bind rendered (SUPER+SHIFT+n)" =
      lib.hasInfix "binds=SUPER+SHIFT,n,switch_layout," bobMango;
    # DMS notifications keeps SUPER+n — no collision with the layout bind.
    "dms notifications keeps SUPER+n" = lib.hasInfix "binds=SUPER,n,spawn_shell," bobMango;

    # ── mango monitors: system-wide default reaches every user ───────────
    # bob inherits both system rules; the key→name default renders `name:HDMI-1`.
    "monitor default reaches user (bob HDMI-1)" =
      lib.hasInfix "monitorrule=name:HDMI-1,width:1920,height:1080,refresh:60,x:0,y:0" bobMango;
    "monitor default reaches user (bob DP-2)" =
      lib.hasInfix "monitorrule=name:DP-2,width:2560,height:1440,x:1920,y:0" bobMango;

    # ── mango monitors: per-user override wins per KEY, sibling still inherits ──
    "per-user monitor override wins (alice HDMI-1)" =
      lib.hasInfix "monitorrule=name:HDMI-1,width:3840,height:2160,refresh:120,x:0,y:0,scale:1.5,rr:3" aliceMango;
    "per-user override replaces the system rule (alice)" =
      !(lib.hasInfix "monitorrule=name:HDMI-1,width:1920" aliceMango);
    "sibling monitor still inherited (alice DP-2)" =
      lib.hasInfix "monitorrule=name:DP-2,width:2560,height:1440,x:1920,y:0" aliceMango;
    # Fractional scale is stripped (proves fmtNum) — must NOT be scale:1.500000.
    "monitor scale rendered stripped (alice)" = lib.hasInfix "scale:1.5," aliceMango;

    # ── mango monitors: the login greeter gets the system-wide layout ────
    "greeter gets system-wide monitors (HDMI-1)" =
      lib.hasInfix "monitorrule=name:HDMI-1,width:1920,height:1080,refresh:60,x:0,y:0" greeterMonitors;
    "greeter gets system-wide monitors (DP-2)" =
      lib.hasInfix "monitorrule=name:DP-2,width:2560,height:1440,x:1920,y:0" greeterMonitors;

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
    "per-user packages empty by default (bob)" = cfg.users.users.bob.packages == [ ];

    # ── monitor renderer unit ────────────────────────────────────────────
    "monitor renderer: anchored name preserved" = lib.hasInfix "name:^eDP-1$" renderedMonitor;
    "monitor renderer: float refresh stripped" = lib.hasInfix "refresh:59.951," renderedMonitor;
    "monitor renderer: float scale stripped" = lib.hasInfix "scale:1.5," renderedMonitor;
    "monitor renderer: transform maps to rr" = lib.hasInfix "rr:1" renderedMonitor;
    "monitor renderer: bool renders as 1" = lib.hasInfix "vrr:1" renderedMonitor;
    "monitor renderer: disabled emits disable:1" =
      lib.hasInfix "monitorrule=name:HDMI-2,disable:1" renderedMonitor;
    "monitor renderer: disabled omits setting fields" = !(lib.hasInfix "width:9999" renderedMonitor);

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
