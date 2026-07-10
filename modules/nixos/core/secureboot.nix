# itera's Secure Boot battery.
#
# A thin, opinionated wrapper over lanzaboote (bundled by
# `modules/nixos/default.nix`), which signs a Unified Kernel Image and installs
# it in place of systemd-boot to give the machine UEFI Secure Boot + measured
# boot. This is the natural capstone to itera's hardening story (nix-mineral
# kernel lockdown + impermanence ephemeral root): it lets the firmware attest
# that only trusted components booted.
#
# Opt-IN (default OFF) — the ONE deliberate exception to itera's opt-out shape.
# Turning Secure Boot on is a multi-step, per-machine operation that CANNOT be
# safely defaulted: it needs the firmware placed in "setup mode" and a one-time
# key enrollment, and getting it wrong makes the machine unbootable. So this
# battery is fully wired but stays off until you opt in and enroll keys:
#
#   1. Enable it:            itera.secureBoot.enable = true;
#   2. Create the keys:      sudo sbctl create-keys
#   3. Enroll (setup mode):  sudo sbctl enroll-keys --microsoft
#   4. Rebuild + reboot, then verify with:  bootctl status  /  sbctl verify
#
# Under impermanence the key bundle lives on tmpfs unless persisted — see
# `itera.impermanence`, which adds `pkiBundle` to the persisted set whenever this
# battery is on, so the enrolled keys survive the ephemeral root.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault mkForce;
  inherit (lib.types) bool str;

  cfg = config.itera.secureBoot;
in
{
  options.itera.secureBoot = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Sign the boot chain with lanzaboote and boot via Secure Boot instead of
        systemd-boot. OFF by default (unlike the rest of itera): enabling requires
        a one-time key enrollment with the firmware in setup mode — see the module
        header for the enrollment steps. Leaving it off keeps plain systemd-boot.
      '';
    };

    pkiBundle = mkOption {
      type = str;
      default = "/var/lib/sbctl";
      description = ''
        Directory holding the Secure Boot signing keys (created by
        {command}`sbctl create-keys`). Must survive reboots — {option}`itera.impermanence`
        persists it automatically while this battery is enabled.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    boot.lanzaboote = {
      enable = mkDefault true;
      pkiBundle = mkDefault cfg.pkiBundle;
    };

    # lanzaboote replaces the bootloader, so the systemd-boot itera.boot installs
    # by default must be turned off. mkForce because itera.boot sets it too.
    boot.loader.systemd-boot.enable = mkForce false;

    # sbctl manages the key bundle and verifies the signed files.
    environment.systemPackages = [ pkgs.sbctl ];
  };
}
