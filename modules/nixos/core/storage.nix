# itera's removable-storage battery: udisks2 + udiskie.
#
# udisks2 is the D-Bus service that lets an unprivileged session mount USB
# drives and other removable media; without it, plugging in a stick does
# nothing. DMS ships no automount agent, so we also install udiskie — the mango
# home battery autostarts it in the session (see `modules/hjem/programs/mango.nix`),
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
  inherit (lib.types) bool strMatching;

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
      type = strMatching "#[0-9a-fA-F]{6}";
      default = "#ffffff";
      example = "#1a1c20";
      description = ''
        Fill color of udiskie's tray icon. White by default, matching the other
        icons on itera's dark DankMaterialShell bar; change it if you switch to a
        light theme. Qt does not recolor tray icons, so it is fixed at build time.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.udisks2.enable = mkDefault true;
    environment.systemPackages = [ pkgs.udiskie ];
  };
}
