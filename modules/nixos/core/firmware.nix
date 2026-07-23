# itera's firmware-update battery.
#
# Stands up fwupd so device firmware (UEFI/BIOS, SSDs, docks, peripherals) can be
# updated from the LVFS via `fwupdmgr`. itera's mango + DankMaterialShell desktop
# has no GNOME Software/Discover, so `fwupdmgr refresh` / `fwupdmgr update` is the
# interface. Complements the build-time firmware bits in hardware.nix (microcode,
# redistributable blobs): those are baked at build time, whereas this updates
# device firmware at runtime.
#
# Opt-out like the other core batteries: on by default with `itera.enable`, values
# set with mkDefault so a server/VM/hardened host can disable it.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.firmware;
in
{
  options.itera.firmware = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable fwupd so device firmware (UEFI/BIOS, SSDs, docks, peripherals) can
        be updated from the LVFS with {command}`fwupdmgr`. On by default whenever
        {option}`itera.enable` is set; set to `false` on a host that should not
        run the fwupd daemon (e.g. a VM or a locked-down box). Note that this only
        makes updates *available* — fwupd never installs firmware on its own.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.fwupd.enable = mkDefault true;
  };
}
