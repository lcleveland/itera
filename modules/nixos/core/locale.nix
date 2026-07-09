# itera's locale battery: time zone, system locale, and NTP time sync.
#
# Sets the machine's time zone, applies one locale across every `LC_*` category
# for consistent formatting, and enables systemd-timesyncd. Gated on the master
# `itera.enable` with `mkDefault` values, so everything is opt-out and overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool str;

  cfg = config.itera.locale;

  # Every LC_* category NixOS exposes via i18n.extraLocaleSettings.
  lcCategories = [
    "LC_ADDRESS"
    "LC_COLLATE"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ];
in
{
  options.itera.locale = {
    timeZone = mkOption {
      type = str;
      default = "America/Chicago";
      example = "Europe/London";
      description = "System time zone as an IANA name (Region/City).";
    };

    defaultLocale = mkOption {
      type = str;
      default = "en_US.UTF-8";
      example = "en_GB.UTF-8";
      description = ''
        Locale applied to {option}`i18n.defaultLocale` and every {command}`LC_*`
        category.
      '';
    };

    timesync.enable = mkOption {
      type = bool;
      default = true;
      description = "Enable network time synchronization (systemd-timesyncd).";
    };
  };

  config = mkIf config.itera.enable {
    time.timeZone = mkDefault cfg.timeZone;

    services.timesyncd.enable = mkDefault cfg.timesync.enable;

    i18n = {
      defaultLocale = mkDefault cfg.defaultLocale;

      extraLocaleSettings = builtins.listToAttrs (
        map (category: {
          name = category;
          value = mkDefault cfg.defaultLocale;
        }) lcCategories
      );
    };
  };
}
