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

      # itera's shell battery makes zsh the default login shell (Oh My Zsh +
      # atuin/zoxide/pay-respects init). Its heavier interactive
      # startup races the serial-console `send_chars` below — the command is typed
      # before the prompt is ready and gets lost. This test is a boot + login smoke
      # test, not a shell test (the shell battery has its own `shell-eval` check),
      # so pin the test user to bash for a deterministic tty interaction.
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
    machine.wait_until_tty_matches("1", "login: ")
    machine.send_chars("test\n")
    machine.wait_until_tty_matches("1", "Password: ")
    machine.send_chars("test\n")
    machine.send_chars("whoami > /tmp/whoami.txt\n")
    machine.wait_for_file("/tmp/whoami.txt")
    assert "test" in machine.succeed("cat /tmp/whoami.txt")
  '';
}
