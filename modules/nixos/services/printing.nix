# itera's printing battery.
#
# Stands up CUPS with mDNS printer discovery so network printers just appear.
# Opt-IN (off by default): not every host has a printer, and running an mDNS
# responder + CUPS is unwanted noise on a server or a hardened box. Turn on with
# `itera.printing.enable = true`.
#
# The `drivers` list defaults to HP's `hplipWithPlugin` (the common office case,
# and what carried over from the older config); override it wholesale for other
# vendors, or extend it with `itera.printing.drivers = [ ... ];`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool listOf package;

  cfg = config.itera.printing;
in
{
  options.itera.printing = {
    enable = mkEnableOption "CUPS printing with mDNS printer discovery";

    drivers = mkOption {
      type = listOf package;
      default = [ pkgs.hplipWithPlugin ];
      defaultText = lib.literalExpression "[ pkgs.hplipWithPlugin ]";
      example = lib.literalExpression "[ pkgs.gutenprint pkgs.brlaser ]";
      description = "Printer driver packages made available to CUPS.";
    };

    gui = mkOption {
      type = bool;
      default = true;
      description = "Install the system-config-printer GUI for managing printers.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services = {
      printing = {
        enable = mkDefault true;
        inherit (cfg) drivers;
      };

      # mDNS discovery so `.local` network printers are found automatically. DMS
      # already turns avahi on (with nssmdns4/6) via mkDefault; setting the same
      # keys here with mkDefault merges cleanly whether or not the desktop is on,
      # and adds the firewall opening printing needs for discovery.
      avahi = {
        enable = mkDefault true;
        nssmdns4 = mkDefault true;
        openFirewall = mkDefault true;
      };

      system-config-printer.enable = mkDefault cfg.gui;
    };
  };
}
