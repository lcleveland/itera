# Evaluation check for itera's shell battery: nushell (default login shell +
# carapace external-command completion) and its per-user home config.
#
# Like the other *-eval checks, we evaluate three NixOS configurations — defaults,
# nushell off, and carapace off — and assert the generated config. `nix build`
# forces evaluation and fails loudly on any false assertion.
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

  # An account so the hjem home layer renders; disko/impermanence stay off.
  mkEval =
    extra:
    mkConfig [
      { itera.users.alice.initialPassword = "changeme"; }
      extra
    ];

  # Defaults: nushell on, default login shell, carapace on.
  base = mkEval { };

  # nushell off: the login shell falls back and every home file drops.
  nushellOff = mkEval { itera.shell.nushell.enable = false; };

  # carapace off: nushell stays, but no completion engine or hookup.
  carapaceOff = mkEval { itera.shell.nushell.carapace.enable = false; };

  hasPkg =
    pname: pkgList:
    builtins.any (p: (p.pname or p.name or "") == pname || lib.hasInfix pname (p.name or "")) pkgList;

  baseFiles = base.hjem.users.alice.xdg.config.files;
  carapaceOffFiles = carapaceOff.hjem.users.alice.xdg.config.files;

  checks = {
    # ── system battery (default on) ──────────────────────────────────────
    "nushell is installed" = hasPkg "nushell" base.environment.systemPackages;
    "carapace is installed" = hasPkg "carapace" base.environment.systemPackages;
    "nushell is the default login shell" = (base.users.defaultUserShell.pname or "") == "nushell";
    "nushell is registered in /etc/shells" = hasPkg "nushell" base.environment.shells;

    # ── home config (default on) ─────────────────────────────────────────
    "config.nu sources carapace init" =
      lib.hasInfix "source carapace-init.nu"
        baseFiles."nushell/config.nu".text;
    "config.nu sets show_banner" = lib.hasInfix "show_banner" baseFiles."nushell/config.nu".text;
    "carapace-init.nu is written" = baseFiles ? "nushell/carapace-init.nu";
    "env.nu is written" = baseFiles ? "nushell/env.nu";

    # ── nushell off → login shell and home files drop ────────────────────
    "nushell off: not the default shell" = (nushellOff.users.defaultUserShell.pname or "") != "nushell";
    "nushell off: not in /etc/shells" = !(hasPkg "nushell" nushellOff.environment.shells);
    "nushell off: no config.nu" = !(nushellOff.hjem.users.alice.xdg.config.files ? "nushell/config.nu");

    # ── carapace off → nushell stays, completion hookup drops ────────────
    "carapace off: nushell still default shell" =
      (carapaceOff.users.defaultUserShell.pname or "") == "nushell";
    "carapace off: carapace not installed" =
      !(hasPkg "carapace" carapaceOff.environment.systemPackages);
    "carapace off: config.nu does not source carapace" =
      !(lib.hasInfix "carapace-init.nu" carapaceOffFiles."nushell/config.nu".text);
    "carapace off: no carapace-init.nu" = !(carapaceOffFiles ? "nushell/carapace-init.nu");
  };

in
mkCheckDrv "itera-nushell-eval" checks
