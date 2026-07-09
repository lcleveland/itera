# itera's networking battery: hostname and NetworkManager.
#
# Names the machine and brings up NetworkManager as the default connection
# manager (works out of the box for both wired and Wi-Fi). Gated on the master
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

  cfg = config.itera.networking;
in
{
  options.itera.networking = {
    hostName = mkOption {
      type = str;
      default = "itera";
      example = "my-machine";
      description = "System hostname.";
    };

    networkmanager.enable = mkOption {
      type = bool;
      default = true;
      description = "Use NetworkManager to manage network connections.";
    };
  };

  config = mkIf config.itera.enable {
    assertions = [
      {
        assertion = cfg.hostName != "";
        message = "itera.networking.hostName must not be empty.";
      }
    ];

    networking = {
      hostName = mkDefault cfg.hostName;
      networkmanager.enable = mkDefault cfg.networkmanager.enable;
    };
  };
}
