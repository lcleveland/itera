# Real EFI boot test for itera's core-boot batteries.
#
# A plain NixOS VM test boots the kernel directly and never touches the boot
# loader, so it cannot prove `itera.boot` works. Here we set
# `virtualisation.useBootLoader` + `useEFIBoot`, which installs systemd-boot onto
# an emulated ESP and boots the guest *through* it under OVMF — genuinely
# exercising the loader itera installs. (Pattern borrowed from nixpkgs'
# nixos/tests/systemd-boot.nix.)
#
# The shared harness in tests/default.nix already imports
# `self.nixosModules.default` and defines/enables the `test` user; this file just
# flips on `itera.enable`, boots via the real loader, and asserts the system
# comes up and the user can log in.
{
  nodes.machine =
    { lib, pkgs, ... }:
    {
      itera.enable = true;

      # This is a boot + login smoke test that drives the serial console with
      # `send_chars`, so pin the test user to bash for a deterministic, minimal
      # tty interaction (the NixOS default is already bash — itera no longer ships
      # a shell battery — but keep this explicit so a future prompt-heavy default
      # can't race the console typing below).
      users.users.test.shell = lib.mkForce pkgs.bashInteractive;

      # This test exercises the core-boot stack and a real tty login; the desktop
      # (on by default with itera.enable) would replace tty login with greetd and
      # pull in the whole graphical closure, so opt out of it here. The desktop has
      # its own boot test in desktop-greeter.nix.
      itera.desktop.dankMaterialShell.enable = false;

      # itera sets `networking.hostName` with mkDefault; the test framework ALSO
      # uses mkDefault (to the node name), so the two collide. Pin it for the test.
      networking.hostName = lib.mkForce "machine";

      # Boot through the installed systemd-boot instead of the test framework's
      # direct-kernel boot.
      virtualisation = {
        useBootLoader = true;
        useEFIBoot = true;
      };

      # A password so the tty login below actually authenticates.
      users.users.test.password = "test";
    };

  testScript = ''
    start_all()

    # Booted all the way to userspace through systemd-boot.
    machine.wait_for_unit("multi-user.target")

    # systemd-boot really was installed onto the ESP.
    machine.succeed("test -e /boot/loader/loader.conf")
    machine.succeed("test -e /boot/EFI/systemd/systemd-bootx64.efi")

    # Core-boot batteries applied their config.
    machine.wait_for_unit("NetworkManager.service")
    machine.succeed("timedatectl show --property=Timezone | grep -q America/Chicago")
    machine.succeed("localectl status | grep -q en_US.UTF-8")

    # The declared user can log in on tty1 with its password.
    machine.wait_until_succeeds("pgrep -f 'agetty.*tty1'")

    # `send_chars` races the console: if agetty is still (re)initialising the
    # tty when we type, the first keystrokes are dropped. A dropped username
    # leaves `login` with an empty/garbage user — it rejects it (in CI this
    # showed up as `FAILED LOGIN ... FOR 'UNKNOWN'`, and pam_securetty then
    # flags the bogus user's tty as "not secure"), never prints "Password: ",
    # and falls back to a fresh "login: ". A dropped command after login has the
    # same effect one step later (the flaky failure #91 first tried to fix by
    # waiting for the shell prompt). Both are the same race, so retry the whole
    # login → password → interactive-shell handshake: a dropped keystroke then
    # costs one more attempt instead of a 900 s wait_until_tty_matches timeout.
    def log_in(_last_try: bool) -> bool:
        machine.wait_until_tty_matches("1", "login: ")
        machine.send_chars("test\n")
        try:
            machine.wait_until_tty_matches("1", "Password: ", timeout=20)
            machine.send_chars("test\n")
            # The interactive shell prompt (`[test@machine:~]$`) confirms the
            # login took before we type the command below.
            machine.wait_until_tty_matches("1", "test@machine", timeout=40)
        except Exception:
            return False
        return True

    retry(log_in, timeout_seconds=180)

    machine.send_chars("whoami > /tmp/whoami.txt\n")
    machine.wait_for_file("/tmp/whoami.txt")
    assert "test" in machine.succeed("cat /tmp/whoami.txt")
  '';
}
