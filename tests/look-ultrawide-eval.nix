# Check for the look's ultrawide support (docs/look.md#ultrawide).
#
# Asserts the aspect class (after rotation, at the 2.0 and 2.8 boundaries),
# the mango tag_rules and cycle presets, the DMS layout settings (notifications,
# gaps, the global bar and the opt-in per-output bars with their fallback
# warning), and the seeded wallpapers: each declared output's variant at its
# exact size and the 16:9 variant for the rest. It also runs the seeder to
# prove a GUI wallpaper survives until the wallpaper token changes.
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
  inherit ((import ../lib { inherit lib; })) mango;

  user = name: extra: {
    users.users.${name} = {
      isNormalUser = true;
      home = "/home/${name}";
    };
    hjem.users.${name}.enable = true;
    itera.users.${name} = extra;
  };
  monitors = {
    # Super-ultrawide.
    "DP-1" = {
      width = 5120;
      height = 1440;
      refresh = 60;
    };
    # Ultrawide, but rotated to portrait: standard.
    "DP-2" = {
      width = 3440;
      height = 1440;
      refresh = 60;
      transform = "90";
    };
    # Ultrawide.
    "HDMI-A-1" = {
      width = 2560;
      height = 1080;
      refresh = 60;
    };
  };
  cfg = mkConfig [
    { itera.programs.mango.monitors = monitors; }
    (user "bob" { look.layout.bar.perOutput = true; })
    (user "alice" { })
    # A size-less monitor and a regex-named one: both fall back.
    (user "carol" {
      look.layout.bar.perOutput = true;
      programs.mango.monitors."eDP-1" = { };
    })
    (user "dave" {
      look.layout.bar.perOutput = true;
      programs.mango.monitors.side = {
        name = "HDMI-A-[2-9]";
        width = 1920;
        height = 1080;
        refresh = 60;
      };
    })
    # A regex-named monitor with a model (a DP-MST dock): keyed by the model.
    (user "hank" {
      look.layout.bar.perOutput = true;
      programs.mango.monitors = {
        "DP-1".enable = false;
        "DP-2".enable = false;
        "HDMI-A-1".enable = false;
        dock = {
          name = "^DP-[0-9]+$";
          model = "XG49DH16C";
          width = 5120;
          height = 1440;
          refresh = 165;
        };
      };
    })
    # Only the mode differs from bob's look, then only the wallpaper.
    (user "frank" { look.mode = "light"; })
    (user "gina" {
      look = {
        mode = "light";
        colors.dark.accent = "#c0ffee";
      };
    })
  ];
  cfgPlain = mkConfig [ (user "erin" { }) ];

  files = c: name: c.hjem.users.${name}.xdg.config.files;
  mangoConf = name: builtins.readFile (files cfg name)."mango/config.conf".source;
  # The drop-in refers to store paths, which fromJSON refuses.
  dms =
    name:
    builtins.fromJSON (
      builtins.unsafeDiscardStringContext (files cfg name)."DankMaterialShell/config.d/00-itera.json".text
    );
  bars = name: (dms name).barConfigs;
  seed = c: name: c.hjem.users.${name}.itera.sessionSeed;
  bob = seed cfg "bob";
  warned = name: lib.any (w: lib.hasPrefix "${name} profile: " w && lib.hasInfix "bar.perOutput" w);
  rule =
    m: new: single:
    "tag_rule=id:*,monitor_name:^${m}$,scroller_default_proportion:${new},scroller_default_proportion_single:${single},scroller_ignore_proportion_single:0";

  evalChecks = mkCheckDrv "itera-look-ultrawide-checks" {
    "below 2.0 is standard" = mango.aspectClass 1999 1000 == "standard";
    "2.0 is ultrawide" = mango.aspectClass 2000 1000 == "ultrawide";
    "below 2.8 is ultrawide" = mango.aspectClass 2799 1000 == "ultrawide";
    "2.8 is super-ultrawide" = mango.aspectClass 2800 1000 == "superUltrawide";
    "16:9 is standard" = mango.aspectClass 3840 2160 == "standard";

    "a 5120x1440 monitor gets the super-ultrawide tag_rule" = lib.hasInfix (rule "DP-1" "0.55" "0.55") (
      mangoConf "alice"
    );
    "an ultrawide monitor gets the ultrawide tag_rule" = lib.hasInfix (rule "HDMI-A-1" "0.5" "0.6") (
      mangoConf "alice"
    );
    "a rotated monitor is classified after rotation" = lib.hasInfix (rule "DP-2" "0.9" "1") (
      mangoConf "alice"
    );
    "a size-less monitor gets no tag_rule" = !lib.hasInfix "monitor_name:^eDP-1$" (mangoConf "carol");
    "a regex-named monitor gets its tag_rule" =
      lib.hasInfix "monitor_name:HDMI-A-[2-9],scroller_default_proportion:0.9," (mangoConf "dave");
    "the cycle presets are global" = lib.hasInfix "\nscroller_proportion_preset=0.33,0.5,0.67,0.9,1\n" (
      mangoConf "alice"
    );
    "itera sets no mango gaps line" = !lib.hasInfix "gappih" (mangoConf "alice");

    "notifications pop up top-center" = (dms "alice").notificationPopupPosition == -1;
    "gaps go to DMS's mango gaps setting" =
      (dms "alice").mangoLayoutGapsOverride == cfg.itera.look.gaps;
    "one full bar on every output by default" =
      lib.length (bars "alice") == 1
      && (builtins.head (bars "alice")).screenPreferences == [ "all" ]
      && (builtins.head (bars "alice")).barLengthMode == "full";
    "per-output bars: one per declared output" =
      lib.sort lib.lessThan (map (b: builtins.head b.screenPreferences) (bars "bob")) == [
        "DP-1"
        "DP-2"
        "HDMI-A-1"
      ];
    "per-output bars are sized by class" = lib.all (
      b:
      if b.screenPreferences == [ "DP-1" ] then
        b.barLengthMode == "percent" && b.barLengthPercent == 60
      else
        b.barLengthMode == "full"
    ) (bars "bob");
    "per-output bars keep the launcher logo" = lib.all (
      b: lib.any (w: w.id or null == "launcherButton" && w ? launcherLogoCustomPath) b.leftWidgets
    ) (bars "bob");
    "per-output bars do not warn" = !warned "bob" cfg.warnings;
    "a size-less monitor falls back with a warning" =
      warned "carol" cfg.warnings && (builtins.head (bars "carol")).screenPreferences == [ "all" ];
    "a regex-named monitor falls back with a warning" =
      warned "dave" cfg.warnings && lib.length (bars "dave") == 1;

    "a regex-named monitor with a model gets a bar keyed by model" =
      !warned "hank" cfg.warnings
      && map (b: b.screenPreferences) (bars "hank") == [ [ "XG49DH16C" ] ]
      && (builtins.head (bars "hank")).barLengthPercent == 60;
    "a regex-named monitor with a model gets a wallpaper keyed by model" =
      lib.attrNames (seed cfg "hank").monitorWallpapersDark == [ "XG49DH16C" ];

    "each declared output gets its own wallpaper" =
      lib.attrNames bob.monitorWallpapersDark == [
        "DP-1"
        "DP-2"
        "HDMI-A-1"
      ]
      && lib.attrNames bob.monitorWallpapersLight == lib.attrNames bob.monitorWallpapersDark;
    "the wallpapers render at each output's size after rotation" =
      lib.hasSuffix "5120x1440.png" bob.monitorWallpapersDark."DP-1"
      && lib.hasSuffix "1440x3440.png" bob.monitorWallpapersLight."DP-2";
    "the global wallpaper is 16:9" = lib.hasSuffix "3840x2160.png" bob.wallpaperPathDark;
    "wallpapers are per mode and per monitor" =
      bob.perModeWallpaper && bob.perMonitorWallpaper && bob.wallpaperPathDark != bob.wallpaperPathLight;
    "without declared monitors only the global wallpaper" =
      !(seed cfgPlain "erin").perMonitorWallpaper && (seed cfgPlain "erin").monitorWallpapersDark == { };
    "a size-less monitor gets no wallpaper of its own" =
      !((seed cfg "carol").monitorWallpapersDark ? "eDP-1");
  };

  # Run the seeders against one scratch home, with a private D-Bus for dconf.
  seeder = name: cfg.hjem.users.${name}.systemd.services.itera-look-seed.serviceConfig.ExecStart;
  dbusConf = pkgs.writeText "session.conf" ''
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
     "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <type>session</type>
      <listen>unix:tmpdir=/tmp</listen>
      <servicedir>${pkgs.dconf}/share/dbus-1/services</servicedir>
      <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
    </busconfig>
  '';
in
pkgs.runCommand "itera-look-ultrawide"
  {
    nativeBuildInputs = [
      pkgs.file
      pkgs.jq
      pkgs.dbus
      pkgs.dconf
    ];
  }
  ''
    : ${evalChecks}
    file -b ${bob.monitorWallpapersDark."DP-1"} | grep -q "^PNG image data, 5120 x 1440,"

    export HOME=$TMPDIR/home
    session=$HOME/.local/state/DankMaterialShell/session.json
    run() { dbus-run-session --config-file=${dbusConf} -- "$1"; }

    # First run: the wallpapers for the starting (dark) mode are current.
    run ${seeder "bob"}
    jq -e '.monitorWallpapers."DP-1" == "${bob.monitorWallpapersDark."DP-1"}"
      and .wallpaperPath == "${bob.wallpaperPathDark}" and .perMonitorWallpaper' $session

    # A wallpaper picked in the GUI survives a mode-only change...
    jq '.wallpaperPathDark = "/mine.png" | .monitorWallpapersDark."DP-1" = "/mine.png"' $session > s
    mv s $session
    run ${seeder "frank"}
    jq -e '.isLightMode and .wallpaperPathDark == "/mine.png" and .monitorWallpapersDark."DP-1" == "/mine.png"' $session

    # ...and a live mode survives a wallpaper-only change, which re-seeds.
    jq '.isLightMode = false' $session > s && mv s $session
    run ${seeder "gina"}
    jq -e '(.isLightMode | not) and .wallpaperPathDark == "${(seed cfg "gina").wallpaperPathDark}"
      and .wallpaperPath == .wallpaperPathDark and .monitorWallpapersDark."DP-1" != "/mine.png"' $session
    touch $out
  ''
