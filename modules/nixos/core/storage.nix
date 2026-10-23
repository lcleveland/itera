# itera's removable-storage battery: udisks2 + udiskie.
#
# udisks2 is the D-Bus service that lets an unprivileged session mount USB
# drives and other removable media; without it, plugging in a stick does
# nothing. DMS ships no automount agent, so we also install udiskie, which a
# per-user systemd unit runs in the mango session (`modules/hjem/storage.nix`),
# gated on this option, so drives mount automatically on insert.
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
  inherit (lib.types) bool nullOr strMatching;

  cfg = config.itera.storage;
in
{
  options.itera.storage = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Enable removable-storage mounting (udisks2 + udiskie automount).";
    };

    trayIconColor = mkOption {
      type = nullOr (strMatching "#[0-9a-fA-F]{6}");
      default = null;
      description = ''
        Fill colour of udiskie's tray icon, as `#rrggbb`. `null` (default) uses
        each user's look `text` colour for their starting mode. Qt does not
        recolour tray icons, so it is fixed at build time and follows neither
        the DMS theme picker nor a runtime mode switch.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.udisks2.enable = mkDefault true;
    environment.systemPackages = [ pkgs.udiskie ];
  };
}
