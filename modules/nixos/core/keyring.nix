# itera's secret-storage battery: GNOME Keyring.
#
# The mango module already routes the Secret portal
# (`org.freedesktop.impl.portal.Secret`) to `gnome-keyring`, but never enables
# the daemon — so secret storage (app logins, saved Wi-Fi PSKs, SSH keys) has
# no backend. This battery completes that half-wired path: it runs the keyring
# daemon, unlocks it from the login password via PAM, and ships Seahorse to
# manage it. DMS's lock screen authenticates against `/etc/pam.d/login`, so
# `login` is the PAM service that matters here.
#
# SSH agent stays off: gnome-keyring already provides an ssh-agent, so
# `programs.ssh.startAgent` would conflict.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# with `mkDefault`, so it is on by default yet overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool listOf str;

  cfg = config.itera.keyring;

  pamServices = builtins.listToAttrs (
    map (name: {
      inherit name;
      value.enableGnomeKeyring = mkDefault cfg.enable;
    }) cfg.pamServices
  );
in
{
  options.itera.keyring = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Enable GNOME Keyring secret storage.";
    };

    pamServices = mkOption {
      type = listOf str;
      default = [ "login" ];
      example = [
        "login"
        "greetd"
      ];
      description = "PAM services that unlock the keyring on login.";
    };

    seahorse.enable = mkOption {
      type = bool;
      default = true;
      description = "Install Seahorse, the GNOME Keyring GUI.";
    };
  };

  config = mkIf config.itera.enable {
    services.gnome.gnome-keyring.enable = mkDefault cfg.enable;
    programs.seahorse.enable = mkDefault (cfg.enable && cfg.seahorse.enable);
    security.pam.services = mkIf cfg.enable pamServices;
  };
}
