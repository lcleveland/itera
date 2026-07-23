# itera's power battery.
#
# Adds UPower, the daemon that reports battery and power-device state over
# D-Bus. The DankMaterialShell battery indicator and its lock-before-suspend
# logic read from it. `power-profiles-daemon` is already enabled by the DMS
# module, but that only switches performance profiles — it is not the battery
# reporter, so UPower is still needed. TLP is deliberately NOT added: it is
# mutually exclusive with power-profiles-daemon.
#
# It also makes the power-profiles-daemon *active profile* survive reboots.
# power-profiles-daemon has no persistence of its own — it only remembers
# transient per-app "profile holds", never the profile you pick by hand, so it
# resets to `balanced` on every boot and the DMS bar's Power switcher choice is
# lost (doubly so under itera's tmpfs impermanence root, where /var/lib is
# wiped anyway). A small oneshot saves the active profile on shutdown and
# re-applies it on boot; the state dir is persisted by the impermanence module.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# with `mkDefault`, so it is on by default yet overridable.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.power;

  ppdctl = lib.getExe' pkgs.power-profiles-daemon "powerprofilesctl";
  # Where the last-active profile is stashed between boots. Added to the
  # impermanence persist set (gated on the same power-profiles-daemon switch)
  # so it survives the wiped tmpfs root.
  stateDir = "/var/lib/itera-power-profile";
  stateFile = "${stateDir}/profile";
in
{
  options.itera.power = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Enable UPower battery / power-device reporting.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.upower.enable = mkDefault true;

    # Persist the power-profiles-daemon active profile across reboots. Gated on
    # the daemon actually being enabled (the DMS module turns it on; a headless
    # host without a desktop has it off), so this is inert where there is no
    # profile to remember. Disable with
    # `systemd.services.itera-power-profile-persist.enable = false`.
    systemd.services.itera-power-profile-persist = mkIf config.services.power-profiles-daemon.enable {
      description = "Persist the power-profiles-daemon active profile across reboots";
      # Companion of the daemon, NOT of multi-user.target. The upstream PPD unit
      # is itself ordered `After=multi-user.target display-manager.target`, so
      # hooking this into multi-user.target while ordering it after PPD forms an
      # ordering cycle — systemd resolves that by DELETING this unit's start job,
      # and it never runs (neither ExecStart on boot nor ExecStop on shutdown).
      # Instead let PPD pull this in (`wantedBy` its service) and order after it:
      # `after` means its D-Bus name is up when we restore on boot, and — since
      # systemd stops units in reverse start order — that this unit's ExecStop
      # runs while the daemon is still alive on shutdown. `requires` keeps the
      # restore meaningless-without-the-daemon invariant.
      wantedBy = [ "power-profiles-daemon.service" ];
      after = [ "power-profiles-daemon.service" ];
      requires = [ "power-profiles-daemon.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Restore on boot: apply the saved profile if we have one. A stale or
        # now-invalid value (hardware changed) just fails the `set` and leaves
        # the daemon's default in place — never fatal.
        ExecStart = pkgs.writeShellScript "itera-restore-power-profile" ''
          if [ -r "${stateFile}" ]; then
            profile="$(cat "${stateFile}")"
            if [ -n "$profile" ]; then
              ${ppdctl} set "$profile" || true
            fi
          fi
        '';
        # Save on shutdown: capture whatever profile is active (including a
        # change just made from the DMS bar). Unclean power loss between the
        # change and shutdown is the only case that is lost.
        ExecStop = pkgs.writeShellScript "itera-save-power-profile" ''
          mkdir -p "${stateDir}"
          ${ppdctl} get > "${stateFile}" || true
        '';
      };
    };
  };
}
