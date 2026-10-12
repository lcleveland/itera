# The look, at activation level (docs/look.md#verification).
#
# Booted checks for what only shows on a running system: the per-user seeder
# (ADR 0004) writing session.json and dconf and re-seeding per key, the
# Plymouth theme and console colours, and the greeter's system-token seed.
# DMS's runtime matugen output and screenshots are deliberately not tested.
#
# Expected colours are literal Tide values from docs/look.md's table, not
# recomputed through lib/look.nix, so a wrong palette or a wrong mapping fails.
#
# The seeder is a user unit pulled in by dms.service at login. A graphical
# login needs a GPU the VM lacks, so the test lingers the `test` user (its
# user manager starts at boot) and starts the unit by hand; each start is one
# "login". The `auto` specialisation is the token change: switching to it and
# logging in again must re-seed the mode over a live toggle, yet keep a live
# wallpaper, whose seed did not change.
{
  nodes.machine =
    { lib, ... }:
    {
      itera.enable = true;
      networking.hostName = lib.mkForce "machine";
      users.users.test.linger = true;

      # A seeded token change. Equal times pin `auto` to dark whatever the VM
      # clock says, so isLightMode is deterministic.
      specialisation.auto.configuration.itera.look = {
        mode = "auto";
        darkFrom = "00:00";
        lightFrom = "00:00";
      };
    };

  testScript = ''
    import json
    import shlex

    def hexes(*h):
        return [int(x[i:i + 2], 16) for x in h for i in (1, 3, 5)]

    # Tide dark terminal slots 0-15 (docs/look.md#palette-tide).
    TERMINAL = [
        "#283238", "#f47b74", "#88d078", "#efca61", "#6db0f4", "#d98cd2", "#65d2d2", "#a9b3b9",
        "#68747b", "#ff9b93", "#a4e596", "#ffe295", "#90c6fe", "#eca5e5", "#89e7e6", "#e2e9ed",
    ]
    DARK_ACCENT = "#4eccd3"
    LIGHT_ACCENT = "#057176"
    DARK_SURFACE_BASE = "#151e24"
    SESSION = "/home/test/.local/state/DankMaterialShell/session.json"

    def as_test(cmd):
        return machine.succeed(
            f"runuser -u test -- env XDG_RUNTIME_DIR=/run/user/$(id -u test) {cmd}"
        )

    def login():
        as_test("systemctl --user daemon-reload")
        as_test("systemctl --user start itera-look-seed.service")

    def session():
        return json.loads(machine.succeed(f"cat {SESSION}"))

    def edit(**changes):
        # Root truncates the file in place, so it stays test's.
        machine.succeed(f"echo {shlex.quote(json.dumps(session() | changes))} > {SESSION}")

    def scheme():
        return as_test("dconf read /org/gnome/desktop/interface/color-scheme").strip()

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    with subtest("seeder writes the mode and wallpapers into session.json and dconf"):
        login()
        s = session()
        assert s["isLightMode"] is False, s
        assert s["themeModeAutoEnabled"] is False, s
        assert s["perModeWallpaper"] is True, s
        assert "itera-wallpaper-3840x2160" in s["wallpaperPathDark"], s
        assert s["wallpaperPath"] == s["wallpaperPathDark"], s
        machine.succeed(f"test -s {s['wallpaperPathDark']}")
        # The system dconf floor is dark too, so also require the user's own
        # database, which only the seeder's write creates.
        machine.succeed("test -s /home/test/.config/dconf/user")
        assert scheme() == "'prefer-dark'", scheme()
        # The session's theme file, which settings.json points DMS at, is Tide.
        theme = json.loads(machine.succeed("cat /home/test/.config/DankMaterialShell/itera-theme.json"))
        assert theme["dark"]["primary"] == DARK_ACCENT, theme
        assert theme["light"]["primary"] == LIGHT_ACCENT, theme

    with subtest("same tokens keep live edits"):
        # What DMS's GUI does: toggle the mode (dconf follows) and pick a wallpaper.
        edit(isLightMode=True, wallpaperPathDark="/live.png")
        as_test("dconf write /org/gnome/desktop/interface/color-scheme \"'default'\"")
        login()
        s = session()
        assert s["isLightMode"] is True, s
        assert s["wallpaperPathDark"] == "/live.png", s
        assert scheme() == "'default'", scheme()

    with subtest("a mode token change re-seeds the mode and keeps the live wallpaper"):
        machine.succeed("/run/current-system/specialisation/auto/bin/switch-to-configuration test")
        login()
        s = session()
        assert s["themeModeAutoEnabled"] is True, s
        assert s["themeModeAutoMode"] == "time", s
        assert s["isLightMode"] is False, s
        assert scheme() == "'prefer-dark'", scheme()
        assert s["wallpaperPathDark"] == "/live.png", s

    with subtest("Plymouth theme is installed"):
        assert "Theme=itera" in machine.succeed("cat /etc/plymouth/plymouthd.conf")
        machine.succeed("test -s /etc/plymouth/themes/itera/frame-0.png")
        script = machine.succeed("cat /etc/plymouth/themes/itera/itera.script")
        line = next(l for l in script.splitlines() if "SetBackgroundTopColor" in l)
        rgb = [round(float(v) * 255) for v in line.split("(")[1].split(")")[0].split(",")]
        assert rgb == hexes(DARK_SURFACE_BASE), line

    with subtest("console.colors are installed"):
        got = [
            [int(v) for v in machine.succeed(f"cat /sys/module/vt/parameters/default_{c}").strip().split(",")]
            for c in ("red", "grn", "blu")
        ]
        want = hexes(*TERMINAL)
        assert got == [want[0::3], want[1::3], want[2::3]], got

    with subtest("greeter seed comes from system tokens"):
        machine.wait_for_unit("greetd.service")
        settings = json.loads(machine.succeed("cat /var/lib/dms-greeter/settings.json"))
        greeter_theme = json.loads(machine.succeed(f"cat {settings['customThemeFile']}"))
        assert greeter_theme["dark"]["primary"] == DARK_ACCENT, greeter_theme
        assert greeter_theme["light"]["primary"] == LIGHT_ACCENT, greeter_theme
        image = settings["lockScreenWallpaperPath"]
        assert "itera-greeter" in image, image
        assert machine.succeed(f"head -c 4 {image} | tail -c 3") == "PNG", image
        greeter_session = json.loads(machine.succeed("cat /var/lib/dms-greeter/session.json"))
        assert greeter_session["isLightMode"] is False, greeter_session
  '';
}
