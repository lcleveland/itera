# Boot test for itera's desktop batteries.
#
# The `desktop-eval` check proves the module wiring statically; this proves the
# result actually boots and that DankMaterialShell's greetd greeter comes up as
# the login manager. We don't drive a full graphical login (that needs a GPU/seat
# the headless test VM lacks) — we assert greetd starts at boot and that its
# generated config launches the `dms-greeter` rendered under mango.
#
# The shared harness (tests/default.nix) already imports
# `self.nixosModules.default`, declares the `test` user, and sets
# `hjem.users.test.enable = true`. The desktop is opt-out (on with `itera.enable`),
# so we just flip that on. We disable itera.hardening to keep the test focused on
# the desktop wiring (nix-mineral can interfere with a graphical stack — see the
# README caveat), and force the hostname to avoid the mkDefault collision the
# core-boot test documents.
{
  nodes.machine =
    { lib, ... }:
    {
      itera.enable = true;
      itera.hardening.enable = false;
      networking.hostName = lib.mkForce "machine";
    };

  testScript = ''
    import re

    start_all()
    machine.wait_for_unit("multi-user.target")

    # The DMS greeter drives greetd; it must come up at boot.
    machine.wait_for_unit("greetd.service")
    machine.succeed("systemctl is-active greetd.service")

    # greetd is configured to launch the dms-greeter script.
    greetd_unit = machine.succeed("systemctl cat greetd.service")
    config_match = re.search(r'--config (\S+greetd\.toml)', greetd_unit)
    assert config_match is not None, greetd_unit

    greetd_config = machine.succeed(f"cat {config_match.group(1)}")
    assert "dms-greeter" in greetd_config, greetd_config

    # …and that greeter renders DankMaterialShell under the mango compositor.
    script_match = re.search(r'command\s*=\s*"([^"]+/bin/dms-greeter)"', greetd_config)
    assert script_match is not None, greetd_config

    script = machine.succeed(f"cat {script_match.group(1)}")
    assert "mango" in script, script
    assert "/share/quickshell/dms" in script, script
  '';
}
