# Shared login user for itera's test systems (VM + bare-metal testhost).
#
# itera is a module *layer* with no host of its own, so this dev-only module is
# NOT part of nixosModules.default — a downstream consumer never sees it. It is
# imported by both test systems (via flake/vm.nix and flake/test-host.nix) so the
# single `itera` login account is defined once and its options stay standardized.
_: {
  # `itera.users.<name>` creates the account AND enables hjem for it, so `itera`
  # inherits every itera home battery (mango autostart → `dms run`, the DMS
  # settings.json, the default keybinds) with the system-wide defaults.
  # Log in as itera / itera (initialPassword defaults to the username — fine for
  # a throwaway test box; this trips the expected "change before deploying"
  # warning).
  itera.users.itera.description = "itera test user";

  # The wipe-every-boot tmpfs root persists a curated subset of every user's home
  # by default (itera.impermanence.homes), so this user's logins/desktop state
  # survive a reboot with no extra wiring here.
}
