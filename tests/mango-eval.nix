# Evaluation check for mango's `renderConfig` (lib/mango.nix).
#
# Calls `renderConfig` with small inputs and asserts on the parsed lines
# (`mangoLines`): key presence, order by list index, or a single field. Expected
# keys and values are written literally, never built from lib, so a mango key
# rename shows up here.
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
    mkCheckDrv
    mangoLines
    ;

  render = args: mangoLines (self.lib.mango.renderConfig ({ xkb = { }; } // args));
  withKey = key: lines: lib.filter (l: l.key == key) lines;
  has = key: lines: withKey key lines != [ ];
  value = key: lines: (builtins.head (withKey key lines)).value;
  # Index of the first line with `key`.
  indexOf = key: lines: lib.lists.findFirstIndex (l: l.key == key) (throw "no ${key} line") lines;

  binds = render {
    settings.keybinds = {
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
  };

  # Plain attrs: no submodule name default, so `name` is given explicitly.
  monitors = render {
    settings.monitors = {
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
  };
  ruleFor =
    match:
    lib.findFirst (l: builtins.head l.fields == match) (throw "no ${match} rule") (
      withKey "monitor_rule" monitors
    );
  primaryFields = (ruleFor "name:^eDP-1$").fields;

  layout = render {
    settings = {
      layout = "tile";
      layoutCycle = [
        "scroller"
        "tile"
      ];
    };
  };

  look.layout = {
    presets = [
      0.5
      1.0
    ];
    proportions.standard = {
      new = 0.5;
      single = 1.0;
    };
  };
  sizedMonitor.DP-1 = {
    name = "^DP-1$";
    width = 2560;
    height = 1440;
  };

  # Every section, to check the order.
  full = render {
    settings = {
      layout = "scroller";
      scrollerFocusCenter = true;
      monitors = sizedMonitor;
      keybinds.k = {
        modifierKeys = [ "SUPER" ];
        keySymbol = "Return";
        mangoCommand = "spawn";
        commandArguments = "foot";
      };
      mousebinds.m = {
        modifierKeys = [ "SUPER" ];
        button = "btn_left";
        mangoCommand = "moveresize";
        commandArguments = "curmove";
      };
      gestures.g = {
        direction = "left";
        mangoCommand = "focusdir";
        commandArguments = "right";
      };
      extraConfig = "focus_cross_tag=1";
    };
    inherit look;
    xkb.layout = "us";
    execOnce = [
      "first"
      "second"
    ];
    cursor = {
      name = "Bibata-Modern-Ice";
      size = 24;
    };
    dmsFragments = true;
  };
  order = [
    "exec_once"
    "monitor_rule"
    "cursor_theme"
    "source_optional"
    "xkb_rules_layout"
    "tag_rule"
    "focus_cross_monitor"
    "bind"
    "mousebind"
    "gesturebind"
    "focus_cross_tag"
  ];
in
mkCheckDrv "itera-mango-eval" {
  # Binds.
  "bind modifiers join with +" =
    (builtins.head (withKey "binds" binds)).fields == [
      "SUPER+SHIFT"
      "q"
      "quit"
      ""
    ];
  "empty bind modifiers render none" =
    (lib.last (withKey "binds" binds)).fields == [
      "none"
      "XF86AudioMute"
      "spawn_shell"
      "true"
    ];
  # DMS's cheatsheet reads a bind's label only from the comment line above it.
  "a bind's description labels it" = (builtins.head (withKey "binds" binds)).label == "Exit mango";
  "a bind without a description has no label" = (lib.last (withKey "binds" binds)).label == null;

  # Monitors.
  "monitor keeps an anchored name" = builtins.elem "name:^eDP-1$" primaryFields;
  "monitor float refresh is tidy" = builtins.elem "refresh:59.951" primaryFields;
  "monitor float scale is tidy" = builtins.elem "scale:1.5" primaryFields;
  "monitor transform maps to rr" = builtins.elem "rr:1" primaryFields;
  "monitor bool renders as 1" = builtins.elem "vrr:1" primaryFields;
  "monitor primary renders" = builtins.elem "primary:1" primaryFields;
  "monitor hdr luminance renders" = builtins.elem "hdr_max_lum:616" primaryFields;
  "a disabled monitor renders only its match and disable:1" =
    (ruleFor "name:HDMI-2").value == "name:HDMI-2,disable:1";

  # Layout.
  "the layout renders one tag_rule per tag" =
    map (l: l.value) (withKey "tag_rule" layout)
    == map (id: "id:${toString id},layout_name:tile") (lib.range 1 9);
  "the layout cycle joins with commas" = value "circle_layout" layout == "scroller,tile";
  "an empty layout cycle renders no circle_layout" =
    !(has "circle_layout" (render {
      settings.layout = "tile";
    }));
  "renderConfig needs no look" =
    let
      noLook = render {
        settings = {
          layout = "tile";
          monitors = sizedMonitor;
        };
      };
    in
    !(has "scroller_proportion_preset" noLook)
    && lib.all (l: lib.hasPrefix "id:" l.value && !(lib.hasPrefix "id:*" l.value)) (
      withKey "tag_rule" noLook
    );
  "the look adds presets and per-monitor proportions" =
    value "scroller_proportion_preset" full == "0.5,1"
    && lib.any (l: lib.hasPrefix "id:*,monitor_name:^DP-1$" l.value) (withKey "tag_rule" full);

  # xkb.
  "xkb variant renders" =
    value "xkb_rules_variant" (render {
      settings = { };
      xkb = {
        layout = "us";
        variant = "colemak_dh";
      };
    }) == "colemak_dh";

  # Absent input renders nothing.
  "no input renders nothing" =
    self.lib.mango.renderConfig {
      settings = { };
      xkb = { };
    } == "";
  "no xkb renders no xkb_rules line" =
    !(lib.any (l: lib.hasPrefix "xkb_rules_" l.key) (render {
      settings.layout = "tile";
    }));
  "no scrollerFocusCenter renders no options" =
    !(has "focus_cross_monitor" layout) && !(has "scroller_focus_center" layout);

  # Order.
  "sections render in order" =
    let
      idx = map (k: indexOf k full) order;
    in
    lib.sort lib.lessThan idx == idx;
  "exec_once keeps command order" =
    map (l: l.value) (withKey "exec_once" full) == [
      "first"
      "second"
    ];
  "the cursor renders its theme and size" =
    value "cursor_theme" full == "Bibata-Modern-Ice" && value "cursor_size" full == "24";
  "the DMS fragments leave binds out" =
    map (l: l.value) (withKey "source_optional" full) == [
      "./dms/colors.conf"
      "./dms/layout.conf"
      "./dms/cursor.conf"
      "./dms/input.conf"
      "./dms/outputs.conf"
      "./dms/windowrules.conf"
    ];
}
