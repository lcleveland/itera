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
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  # ── SSH daemon ────────────────────────────────────────────────────────────
  # Password auth ON: both hosts log in as itera/itera (weak test password by
  # design), so key setup would just be friction. Root login
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

  # ── The full `itera` command ───────────────────────────────────────────────
  # These are itera's own test hosts, so they want the FULL dispatcher — the one
  # that also carries the `testhost` verbs (`itera testhost rebuild` rebuilds the
  # box in place from itera's flake; `itera testhost install` is the ISO
  # installer). So opt out of the consumer `itera.cli` battery (which would
  # install the testhost-less build) and bake the full package instead.
  #
  # The full package is pulled from `inputs.self.packages` (threaded in via
  # `specialArgs` in flake/vm.nix and flake/test-host.nix) so it is the same
  # package `nix run .#itera` builds — no duplicate definition here.
  itera.cli.enable = false;

  environment.systemPackages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.itera
  ];

  # Tab-completion for the full command. carapace (itera's external completer in
  # nushell — see modules/nixos/core/shell/nushell.nix) auto-loads specs from
  # ~/.config/carapace/specs/; drop the FULL spec (with `testhost`) there for the
  # login user. Gated on carapace being enabled. `itera` is the sole account on
  # the test hosts (dev/test-user.nix). Consumer hosts get the testhost-less spec
  # via the `itera.programs.itera` home battery instead.
  hjem.users.itera.xdg.config.files = lib.mkIf config.itera.shell.nushell.carapace.enable {
    "carapace/specs/itera.yaml" = {
      source = ../cli/itera.carapace.yaml;
      clobber = true;
    };
  };
}
