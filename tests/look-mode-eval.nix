# Evaluation check for look mode seeding (docs/look.md#light-dark-and-auto).
#
# Asserts the per-user seeder (its unit, ordering and seeded keys per mode),
# the DMS-disabled auto fallback, the GTK battery (no GTK_THEME, adw-gtk3, the
# system dconf floor) and the `theme.dark` shim. It also runs the seeder
# against a scratch session.json to prove it merges, writes dconf and re-seeds
# only when the seed changes.
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

  user = name: extra: {
    users.users.${name} = {
      isNormalUser = true;
      home = "/home/${name}";
    };
    hjem.users.${name}.enable = true;
    itera.users.${name} = extra;
  };
  users = [
    (user "bob" { })
    (user "alice" { look.mode = "light"; })
    (user "carol" { look.mode = "auto"; })
    (user "dave" {
      look = {
        mode = "auto";
        latitude = 40.7;
        longitude = -74.0;
      };
    })
  ];

  cfg = mkConfig users;
  cfgLight = mkConfig [ { itera.look.mode = "light"; } ];
  cfgNoDms = mkConfig (users ++ [ { itera.desktop.dankMaterialShell.enable = false; } ]);
  cfgOldDark = mkConfig [ { itera.desktop.theme.dark = false; } ];
  cfgGtkTheme = mkConfig [ { environment.sessionVariables.GTK_THEME = "Adwaita:dark"; } ];

  unit = c: name: c.hjem.users.${name}.systemd.services.itera-look-seed or null;
  seed = name: cfg.hjem.users.${name}.itera.sessionSeed;
  floor =
    c:
    lib.findFirst (s: s."org/gnome/desktop/interface".color-scheme or null != null) { } (
      map (d: d.settings or { }) c.programs.dconf.profiles.user.databases
    );
  failing = c: map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);

  # Run bob's seeder against a scratch home, with a private D-Bus serving
  # dconf, then change the seed and run it again.
  seeder = name: (unit cfg name).serviceConfig.ExecStart;
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
  seedRun =
    pkgs.runCommand "itera-look-seed-run"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.dbus
          pkgs.dconf
        ];
      }
      ''
        export HOME=$TMPDIR/home
        session=$HOME/.local/state/DankMaterialShell/session.json
        mkdir -p $(dirname $session)
        echo '{"weatherLocation":"Oslo","isLightMode":true}' > $session
        run() { dbus-run-session --config-file=${dbusConf} -- sh -c "$1 && dconf read /org/gnome/desktop/interface/color-scheme"; }

        # First run seeds dark and keeps unrelated keys.
        [ "$(run ${seeder "bob"})" = "'prefer-dark'" ]
        jq -e '.weatherLocation == "Oslo" and .isLightMode == false and .themeModeAutoEnabled == false' $session

        # A live toggle survives the next run with the same seed.
        jq '.isLightMode = true' $session > s && mv s $session
        run ${seeder "bob"}
        jq -e '.isLightMode == true' $session

        # A changed seed (alice's light mode) seeds once more.
        [ "$(run ${seeder "alice"})" = "'default'" ]
        jq -e '.isLightMode == true and .weatherLocation == "Oslo"' $session

        # Auto seeds the mode for the time of login.
        run ${seeder "carol"}
        jq -e '.themeModeAutoEnabled and (.isLightMode | type == "boolean")' $session

        # An unreadable session.json is left alone.
        echo 'not json' > $session
        ! run ${seeder "bob"}
        [ "$(cat $session)" = "not json" ]
        touch $out
      '';
in
pkgs.runCommand "itera-look-mode-eval" {
  checks = mkCheckDrv "itera-look-mode-checks" {
    "the seeder is a oneshot ordered before dms.service" =
      (unit cfg "bob").serviceConfig.Type == "oneshot"
      && builtins.elem "dms.service" (unit cfg "bob").before
      && builtins.elem "dms.service" (unit cfg "bob").wantedBy;
    "dark seeds dark and turns auto off" =
      seed "bob" == {
        isLightMode = false;
        themeModeAutoEnabled = false;
      };
    "light seeds light" = (seed "alice").isLightMode;
    "auto seeds the time schedule by default" =
      seed "carol" == {
        themeModeAutoEnabled = true;
        themeModeAutoMode = "time";
        themeModeStartHour = 18;
        themeModeStartMinute = 0;
        themeModeEndHour = 6;
        themeModeEndMinute = 0;
        themeModeShareGammaSettings = false;
      };
    "auto with coordinates seeds location mode" =
      seed "dave" == {
        themeModeAutoEnabled = true;
        themeModeAutoMode = "location";
        latitude = 40.7;
        longitude = -74.0;
        nightModeUseIPLocation = false;
      };
    "with DMS disabled there is no seeder" = unit cfgNoDms "carol" == null;
    "with DMS disabled auto warns" = builtins.any (lib.hasInfix "starts dark") cfgNoDms.warnings;
    "auto with DMS on does not warn" = !builtins.any (lib.hasInfix "starts dark") cfg.warnings;
    "DMS follows the portal" = cfg.itera.programs.dankMaterialShell.settings.syncModeWithPortal;

    "GTK_THEME is unset" = !(cfg.environment.sessionVariables ? GTK_THEME);
    "GTK_THEME cannot come back while DMS is on" = builtins.any (lib.hasInfix "GTK_THEME") (
      failing cfgGtkTheme
    );
    "adw-gtk3 is installed" = builtins.elem "adw-gtk3" (map lib.getName cfg.environment.systemPackages);
    "the system dconf floor is dark" =
      (floor cfg)."org/gnome/desktop/interface".color-scheme == "prefer-dark";
    "the system dconf floor follows a light look" =
      (floor cfgLight)."org/gnome/desktop/interface".color-scheme == "default";
    "theme.dark = false becomes look.mode = light" = cfgOldDark.itera.look.mode == "light";
    "zed follows a light look" = cfgLight.itera.programs.zed.settings.theme.mode == "light";
  };
  inherit seedRun;
} "touch $out"
