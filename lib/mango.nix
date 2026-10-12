# mango (MangoWC) keybind helpers for itera.
#
# Provides the shared keybind *type* and a renderer that turns a set of
# structured keybind declarations into the `key=value` lines mango expects in
# {file}`$XDG_CONFIG_HOME/mango/config.conf`.
#
# The same `keybindType` is consumed by both levels of the curated mango options
# — the system-wide default `itera.programs.mango.keybinds` and the per-user
# `itera.users.<name>.programs.mango.keybinds` (both NixOS class, generated once
# by the curated-program framework). `lib.types.submodule` is class-agnostic, so a
# single shared value is fine; do NOT pin `_class` on it.
{ lib }:
let
  inherit (lib) concatStringsSep mapAttrsToList;

  # MangoWC's built-in tiling layouts (see mango's docs/window-management/layouts).
  # Used to build the `enum` type for the layout options in both mango batteries.
  supportedLayouts = [
    "tile"
    "scroller"
    "monocle"
    "grid"
    "deck"
    "center_tile"
    "vertical_tile"
    "right_tile"
    "vertical_scroller"
    "vertical_grid"
    "vertical_deck"
    "dwindle"
    "fair"
    "vertical_fair"
  ];

  # A MangoWC bind directive. Its config key is `bind` plus any flag letters, so
  # a bind with `flagModifiers = [ "s" ]` renders under the key `binds`.
  #
  #   <bind-key>=<MOD+MOD>,<key>,<command>,<arguments>
  #
  # with an empty modifier list rendered as the literal `none` and a null
  # argument rendered as the empty string. Mirrors MangoWC's config syntax.
  keybindType = lib.types.submodule (_: {
    options = {
      modifierKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "SUPER"
          "SHIFT"
        ];
        description = "Modifier keys joined with `+` (e.g. `[ \"SUPER\" \"SHIFT\" ]`). Empty renders as `none`.";
      };

      keySymbol = lib.mkOption {
        type = lib.types.str;
        example = "Return";
        description = "Key symbol such as `Return`, `q`, or `space`.";
      };

      mangoCommand = lib.mkOption {
        type = lib.types.str;
        example = "spawn";
        description = "MangoWC command (e.g. `spawn`, `killclient`, `quit`, `spawn_shell`).";
      };

      commandArguments = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "foot";
        description = "Optional command arguments. `null` renders as the empty string.";
      };

      flagModifiers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "l"
            "r"
            "s"
            "p"
            "c"
          ]
        );
        default = [ ];
        example = [ "s" ];
        description = "MangoWC bind flags appended to the `bind` key: l (lock), r (release), s (keysym), p (pass), c (allow conflict — must be set on every bind sharing the key).";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Open terminal";
        description = "Label for DankMaterialShell's keybind cheatsheet, rendered as a `# comment` on the line above the bind (DMS reads labels only from there).";
      };
    };
  });

  # Render a single keybind into its `<bind-key>=<value>` line. Optional fields
  # fall back with `or` so the helper also works on plain (non-submodule) attrs.
  mkBindLine =
    kb:
    let
      flags = kb.flagModifiers or [ ];
      modifierKeys = kb.modifierKeys or [ ];
      commandArguments = kb.commandArguments or null;
      bindKey = "bind" + lib.concatStrings flags;
      modifiers = if modifierKeys == [ ] then "none" else concatStringsSep "+" modifierKeys;
      arguments = if commandArguments == null then "" else commandArguments;
      description = kb.description or null;
    in
    lib.optionalString (description != null) "# ${description}\n"
    + "${bindKey}=${modifiers},${kb.keySymbol},${kb.mangoCommand},${arguments}";

  # Render a name-keyed attrset of keybinds into config.conf lines (one per
  # bind). The names are organisational only — they never reach the file.
  renderKeybinds = keybinds: concatStringsSep "\n" (mapAttrsToList (_: mkBindLine) keybinds);

  # A MangoWC mouse button bind. Renders as
  #
  #   mousebind=<MOD+MOD>,<button>,<command>,<arguments>
  #
  # e.g. SUPER+left-drag moves a window:
  #   mousebind=SUPER,btn_left,moveresize,curmove
  mouseBindType = lib.types.submodule (_: {
    options = {
      modifierKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "SUPER" ];
        description = "Modifier keys joined with `+` (e.g. `[ \"SUPER\" ]`). Empty renders as `none`.";
      };

      button = lib.mkOption {
        type = lib.types.str;
        example = "btn_left";
        description = "Mouse button: `btn_left`, `btn_right`, `btn_middle`, `btn_side`, `btn_extra`, `btn_forward`, `btn_back`, `btn_task`, or `code:<N>`.";
      };

      mangoCommand = lib.mkOption {
        type = lib.types.str;
        example = "moveresize";
        description = "MangoWC command to run (e.g. `moveresize`, `killclient`).";
      };

      commandArguments = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "curmove";
        description = "Optional command arguments. `null` renders as the empty string.";
      };
    };
  });

  mkMouseBindLine =
    mb:
    let
      modifierKeys = mb.modifierKeys or [ ];
      commandArguments = mb.commandArguments or null;
      modifiers = if modifierKeys == [ ] then "none" else concatStringsSep "+" modifierKeys;
      arguments = if commandArguments == null then "" else commandArguments;
    in
    "mousebind=${modifiers},${mb.button},${mb.mangoCommand},${arguments}";

  renderMouseBinds =
    mousebinds: concatStringsSep "\n" (mapAttrsToList (_: mkMouseBindLine) mousebinds);

  # A MangoWC touchpad gesture bind. Renders as
  #
  #   gesturebind=<MOD+MOD>,<direction>,<fingers>,<command>,<arguments>
  #
  # mirroring MangoWC's config syntax (an empty modifier list renders as the
  # literal `none`, a null argument as the empty string). e.g. a 3-finger swipe
  # left that focuses the window to the right:
  #   gesturebind=none,left,3,focusdir,right
  gestureType = lib.types.submodule (_: {
    options = {
      modifierKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "SUPER" ];
        description = "Modifier keys joined with `+` (e.g. `[ \"SUPER\" ]`). Empty renders as `none`.";
      };

      direction = lib.mkOption {
        type = lib.types.enum [
          "left"
          "right"
          "up"
          "down"
        ];
        example = "left";
        description = "Swipe direction.";
      };

      fingerCount = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        example = 3;
        description = "Number of fingers on the touchpad for this gesture.";
      };

      mangoCommand = lib.mkOption {
        type = lib.types.str;
        example = "focusdir";
        description = "MangoWC command to run (e.g. `focusdir`, `switch_layout`).";
      };

      commandArguments = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "right";
        description = "Optional command arguments. `null` renders as the empty string.";
      };
    };
  });

  # Render a single gesture into its `gesturebind=` line. Optional fields fall
  # back with `or` so the helper also works on plain (non-submodule) attrs.
  mkGestureLine =
    g:
    let
      modifierKeys = g.modifierKeys or [ ];
      commandArguments = g.commandArguments or null;
      modifiers = if modifierKeys == [ ] then "none" else concatStringsSep "+" modifierKeys;
      arguments = if commandArguments == null then "" else commandArguments;
    in
    "gesturebind=${modifiers},${g.direction},${toString (g.fingerCount or 3)},${g.mangoCommand},${arguments}";

  # Render a name-keyed attrset of gestures into config.conf lines (one per
  # gesture). The names are organisational only — they never reach the file.
  renderGestures = gestures: concatStringsSep "\n" (mapAttrsToList (_: mkGestureLine) gestures);

  # Render the XKB keyboard config into mango's `xkb_rules_*` lines. Driven by the
  # system `itera.keyboard` battery (via `services.xserver.xkb`) so the mango
  # session and the login greeter match the console layout. Empty fields are
  # omitted; an all-empty input renders "" so no lines are emitted (mango keeps
  # its default `us`).
  renderXkb =
    {
      layout ? "",
      variant ? "",
      options ? "",
    }:
    concatStringsSep "\n" (
      lib.optional (layout != "") "xkb_rules_layout=${layout}"
      ++ lib.optional (variant != "") "xkb_rules_variant=${variant}"
      ++ lib.optional (options != "") "xkb_rules_options=${options}"
    );

  # Friendly rotation/flip names → MangoWC's numeric `rr` transform (see the
  # transform table in mango's docs/configuration/monitors).
  monitorTransforms = {
    "normal" = 0;
    "90" = 1;
    "180" = 2;
    "270" = 3;
    "flipped" = 4;
    "flipped-90" = 5;
    "flipped-180" = 6;
    "flipped-270" = 7;
  };

  # `builtins.toString` pads floats to six decimals ("1.5" → "1.500000"); ints
  # render clean ("144"). Strip trailing fractional zeros so both config.conf
  # and the eval tests stay tidy (`scale:1.5`, not `scale:1.500000`).
  fmtNum =
    v:
    if lib.isInt v then
      toString v
    else
      let
        parts = lib.splitString "." (toString v);
        intPart = builtins.head parts;
        frac = builtins.elemAt parts 1;
        m = builtins.match "(.*[^0])0*" frac; # null when frac is all zeros
      in
      if m == null then intPart else "${intPart}.${builtins.head m}";

  # A MangoWC `monitor_rule=` entry. `name` is a regex; make/model/serial are
  # exact strings. If several are set, ALL must match for the rule to apply, and
  # mango applies only the FIRST matching rule per output. The remaining fields
  # configure the matched output. The attribute key defaults into `name` as an
  # anchored regex (`^key$`), so keying a monitor by its connector name matches
  # exactly that connector — `DP-1` never also catches `eDP-1`.
  #
  #   monitor_rule=name:VAL,width:VAL,height:VAL,refresh:VAL,x:VAL,y:VAL,...
  monitorRuleType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          example = "^eDP-1$";
          description = ''
            Output match regex (connector name). Defaults to the attribute key,
            escaped and anchored (`^eDP-1$`) so it matches that connector exactly.
            Set it to an unanchored pattern (e.g. `HDMI-A-.*`) to match several.
          '';
        };
        make = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Match the output's manufacturer (exact string). Use `wlr-randr` to find it.";
        };
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Match the output's model (exact string). Use `wlr-randr` to find it.";
        };
        serial = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Match the output's serial number (exact string). Use `wlr-randr` to find it.";
        };

        width = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 1920;
          description = "Mode width in pixels. Set width, height and refresh together or not at all (mango rejects a partial mode).";
        };
        height = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 1080;
          description = "Mode height in pixels. Set width, height and refresh together or not at all (mango rejects a partial mode).";
        };
        refresh = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
          default = null;
          example = 59.951;
          description = "Refresh rate in Hz. Set width, height and refresh together or not at all (mango rejects a partial mode).";
        };
        x = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 0;
          description = ''
            X position in the global layout. Do NOT use negative coordinates if you
            run XWayland apps — a known XWayland bug breaks click events. Arrange
            monitors from `0,0` into positive space.
          '';
        };
        y = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 0;
          description = ''
            Y position in the global layout. Do NOT use negative coordinates if you
            run XWayland apps (see `x`).
          '';
        };
        scale = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
          default = null;
          example = 1.5;
          description = "Fractional scale factor.";
        };

        vrr = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Variable refresh rate (adaptive sync).";
        };
        hdr = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "High dynamic range. See also the `hdr*` luminance fields.";
        };
        hdrForce = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Enable HDR even when the EDID does not advertise BT.2020/PQ (MangoWC's `hdr_force`).";
        };
        hdrMinLum = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
          default = null;
          example = 0.05;
          description = "Mastering display minimum luminance in cd/m² (MangoWC's `hdr_min_lum`).";
        };
        hdrMaxLum = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
          default = null;
          example = 616;
          description = "Mastering display peak luminance in cd/m², also sent as max_cll (MangoWC's `hdr_max_lum`).";
        };
        hdrMaxAvgLum = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
          default = null;
          example = 400;
          description = "Max frame-average light level (max_fall) in cd/m² (MangoWC's `hdr_max_avg_lum`).";
        };
        primary = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = ''
            Make this the X11 (RandR) primary output for XWayland — fullscreen
            games use it as their coordinate origin. If several rules set it, the
            first matching one wins.
          '';
        };
        customMode = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = ''
            Treat width/height/refresh as a custom (non-advertised) mode
            (MangoWC's `custom`). Not supported on all displays — may cause a black
            screen.
          '';
        };
        transform = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum (lib.attrNames monitorTransforms));
          default = null;
          example = "90";
          description = ''
            Output rotation/flip, rendered as MangoWC's `rr`. One of: normal, 90,
            180, 270 (counter-clockwise degrees), flipped, flipped-90, flipped-180,
            flipped-270.
          '';
        };
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether the output is enabled. `false` renders `disable:1`.";
        };
      };
      config.name = lib.mkDefault "^${lib.escapeRegex name}$";
    }
  );

  # Render a single monitor into its `monitor_rule=` line. Optional fields fall
  # back with `or` so the helper also works on plain (non-submodule) attrs, which
  # keeps it directly unit-testable. Only set (non-null) fields are emitted; a
  # disabled output emits its match fields plus `disable:1` and nothing else.
  mkMonitorRuleLine =
    m:
    let
      b = v: if v then "1" else "0";
      enabled = m.enable or true;
      matchParts =
        lib.optional ((m.name or null) != null) "name:${m.name}"
        ++ lib.optional ((m.make or null) != null) "make:${m.make}"
        ++ lib.optional ((m.model or null) != null) "model:${m.model}"
        ++ lib.optional ((m.serial or null) != null) "serial:${m.serial}";
      setParts =
        lib.optional ((m.width or null) != null) "width:${toString m.width}"
        ++ lib.optional ((m.height or null) != null) "height:${toString m.height}"
        ++ lib.optional ((m.refresh or null) != null) "refresh:${fmtNum m.refresh}"
        ++ lib.optional ((m.x or null) != null) "x:${toString m.x}"
        ++ lib.optional ((m.y or null) != null) "y:${toString m.y}"
        ++ lib.optional ((m.scale or null) != null) "scale:${fmtNum m.scale}"
        ++ lib.optional ((m.vrr or null) != null) "vrr:${b m.vrr}"
        ++ lib.optional ((m.hdr or null) != null) "hdr:${b m.hdr}"
        ++ lib.optional ((m.hdrForce or null) != null) "hdr_force:${b m.hdrForce}"
        ++ lib.optional ((m.hdrMinLum or null) != null) "hdr_min_lum:${fmtNum m.hdrMinLum}"
        ++ lib.optional ((m.hdrMaxLum or null) != null) "hdr_max_lum:${fmtNum m.hdrMaxLum}"
        ++ lib.optional ((m.hdrMaxAvgLum or null) != null) "hdr_max_avg_lum:${fmtNum m.hdrMaxAvgLum}"
        ++ lib.optional ((m.primary or null) != null) "primary:${b m.primary}"
        ++ lib.optional ((m.customMode or null) != null) "custom:${b m.customMode}"
        ++ lib.optional ((m.transform or null) != null) "rr:${toString monitorTransforms.${m.transform}}";
      parts = matchParts ++ (if enabled then setParts else [ "disable:1" ]);
    in
    "monitor_rule=${concatStringsSep "," parts}";

  # Render a name-keyed attrset of monitor rules into config.conf lines (one
  # `monitor_rule=` per output). A bare `monitor_rule=` (no fields at all) is
  # dropped defensively — a real submodule value always carries its key-derived
  # `name`, so this only guards degenerate plain-attrs input.
  renderMonitorRules =
    monitors:
    concatStringsSep "\n" (
      lib.filter (l: l != "monitor_rule=") (mapAttrsToList (_: mkMonitorRuleLine) monitors)
    );

  # MangoWC has no single "default layout" key — the startup layout is set per
  # tag via `tag_rule=id:N,layout_name:<layout>`. Render one such line per tag to
  # give every tag the same default. `tagCount` defaults to 9 to match itera's
  # `SUPER+1..9` tag binds (see `tags` in modules/nixos/desktop/mango.nix); keep
  # the two in sync.
  mkTagLayoutLines =
    {
      layout,
      tagCount ? 9,
    }:
    concatStringsSep "\n" (
      map (id: "tag_rule=id:${toString id},layout_name:${layout}") (lib.range 1 tagCount)
    );

  # Write a config file and parse it with `mango -p`, failing the build on any
  # error mango reports (unknown key, bad value, keybind conflict). `-p` only
  # parses — no display or runtime dir needed, so it runs in the sandbox.
  validateConfig =
    {
      pkgs,
      mango,
      text,
      name ? "mango-config.conf",
    }:
    pkgs.runCommand name
      {
        inherit text;
        passAsFile = [ "text" ];
      }
      ''
        cp "$textPath" "$out"
        HOME="$TMPDIR" ${mango}/bin/mango -p -c "$out"
      '';

  # Render the `circle_layout=` line that `switch_layout` cycles through. An
  # empty list renders as "" so the line is omitted entirely (mango then cycles
  # all built-in layouts).
  mkCircleLayoutLine =
    layouts: if layouts == [ ] then "" else "circle_layout=${concatStringsSep "," layouts}";

  # Declared outputs (docs/look.md#ultrawide): each enabled monitor with its
  # size after rotation, its aspect class (null without a width and height:
  # it gets the global defaults) and its connector name (null when `name` is a
  # regex rather than one exact, anchored connector).
  rotated = [
    "90"
    "270"
    "flipped-90"
    "flipped-270"
  ];
  aspectClass =
    width: height:
    let
      r = width * 1.0 / height;
    in
    if r >= 2.8 then
      "superUltrawide"
    else if r >= 2.0 then
      "ultrawide"
    else
      "standard";
  declaredOutputs =
    monitors:
    map (
      m:
      let
        sized = (m.width or null) != null && (m.height or null) != null;
        turn = builtins.elem (m.transform or null) rotated;
        width = if turn then m.height else m.width;
        height = if turn then m.width else m.height;
        connector = builtins.match "\\^([A-Za-z0-9_-]+)\\$" (m.name or "");
      in
      {
        monitor = m;
        connector = if connector == null then null else builtins.head connector;
        class = if sized then aspectClass width height else null;
      }
      // lib.optionalAttrs sized { inherit width height; }
    ) (lib.filter (m: m.enable or true) (lib.attrValues monitors));

  # This user's monitors: the system set, with per-user entries of the same
  # key replacing it wholesale.
  userMonitors =
    osConfig: name:
    (osConfig.itera.programs.mango.monitors or { })
    // (osConfig.itera.users.${name}.programs.mango.monitors or { });

  # Per-monitor scroller proportions by aspect class: one `tag_rule` for every
  # tag of each sized output, matched on its `name` regex (and make, model,
  # serial). `proportions.<class>` is `{ new; single; }`.
  mkAspectTagRules =
    proportions: outputs:
    concatStringsSep "\n" (
      map (
        o:
        let
          m = o.monitor;
          p = proportions.${o.class};
        in
        concatStringsSep "," (
          [
            "tag_rule=id:*"
            "monitor_name:${m.name}"
          ]
          ++ lib.optional ((m.make or null) != null) "monitor_make:${m.make}"
          ++ lib.optional ((m.model or null) != null) "monitor_model:${m.model}"
          ++ lib.optional ((m.serial or null) != null) "monitor_serial:${m.serial}"
          ++ [
            "scroller_default_proportion:${fmtNum p.new}"
            "scroller_default_proportion_single:${fmtNum p.single}"
            "scroller_ignore_proportion_single:0"
          ]
        )
      ) (lib.filter (o: o.class != null) outputs)
    );

  # The scroller widths `switch_proportion_preset` cycles through.
  mkProportionPresetLine =
    presets: "scroller_proportion_preset=${lib.concatMapStringsSep "," fmtNum presets}";
in
{
  inherit
    keybindType
    mkBindLine
    renderKeybinds
    mouseBindType
    mkMouseBindLine
    renderMouseBinds
    gestureType
    mkGestureLine
    renderGestures
    renderXkb
    supportedLayouts
    mkTagLayoutLines
    mkCircleLayoutLine
    aspectClass
    declaredOutputs
    userMonitors
    mkAspectTagRules
    mkProportionPresetLine
    monitorRuleType
    mkMonitorRuleLine
    renderMonitorRules
    validateConfig
    ;
}
