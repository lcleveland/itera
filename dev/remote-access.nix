# Remote access for itera's test systems — SSH in + update in place.
#
# itera is a module *layer*, not a host, so this is not something a downstream
# consumer sees: it is dev-only tooling shared by the two test systems (the QEMU
# `itera-vm` and the bare-metal `itera-testhost`), wired into both via their
# `modules` lists in `flake/vm.nix` and `flake/test-host.nix`. It exists so you
# (or Claude) can ssh in to troubleshoot a running test box and rebuild it from
# the latest remote config without reinstalling from the live ISO.
#
# Deliberately NOT a consumer-facing `itera.*` battery: exposing an SSH daemon by
# default would be a second exception to itera's opt-out shape (secureboot.nix is
# documented as "the ONE deliberate exception"), so a network service stays scoped
# to these throwaway test hosts.
#
# SSH host keys already survive the tmpfs-root wipe — impermanence's curated
# defaults persist `/etc/ssh/ssh_host_*` — so clients won't hit host-key-changed
# warnings across reboots. Nothing to add here for that.
{
  lib,
  pkgs,
  ...
}:
{
  # ── SSH daemon ────────────────────────────────────────────────────────────
  # Password auth ON: these hosts log in as tester/tester and dev/dev (weak
  # test passwords by design), so key setup would just be friction. Root login
  # stays OFF — sudo from the wheel user instead. Both toggles are mkForce'd so
  # they win over any nix-mineral hardening default (itera.hardening is on by
  # default on these hosts and hardens sshd).
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce true;
      PermitRootLogin = lib.mkForce "no";
    };
  };

  # NixOS's default firewall is on and does not open 22; open it so the daemon is
  # actually reachable. (On the VM this is still gated behind the QEMU port
  # forward set in dev/vm.nix.)
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── In-place remote update command ─────────────────────────────────────────
  # `itera-update` rebuilds the machine from the newest remote flake commit — the
  # sibling of the install path, for iterating without reinstalling. Script and
  # usage live in dev/update-itera.sh (same readFile pattern as the installer in
  # flake/test-host.nix).
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "itera-update";
      text = builtins.readFile ./update-itera.sh;
    })
  ];
}
