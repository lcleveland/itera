# itera's secret-storage battery: GNOME Keyring.
#
# The mango module already routes the Secret portal
# (`org.freedesktop.impl.portal.Secret`) to `gnome-keyring`, but never enables
# the daemon — so secret storage (app logins, saved Wi-Fi PSKs, SSH keys) has
# no backend. This battery completes that half-wired path: it runs the keyring
# daemon, unlocks it from the login password via PAM, and ships Seahorse to
# manage it.
#
# Two PAM services matter, because the keyring has to be unlocked at each surface
# that takes your password: `login` for the initial login, and `dankshell` for
# DMS's lock screen (declared by the DankMaterialShell battery — DMS stopped
# authenticating the lock screen against `/etc/pam.d/login` and now uses its own
# service). Without the second one, re-authenticating at the lock screen would
# leave a keyring that was locked in the meantime still locked.
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
  inherit (lib.options) mkOption literalExpression;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool listOf str;

  cfg = config.itera.keyring;
  dmsCfg = config.itera.desktop.dankMaterialShell;

  pamServices = builtins.listToAttrs (
    map (name: {
      inherit name;
      value.enableGnomeKeyring = mkDefault true;
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
      default = [ "login" ] ++ lib.optional dmsCfg.enable "dankshell";
      defaultText = literalExpression ''
        [ "login" ] ++ lib.optional config.itera.desktop.dankMaterialShell.enable "dankshell"
      '';
      example = [
        "login"
        "greetd"
      ];
      description = ''
        PAM services that unlock the keyring. `login` covers the initial login;
        `dankshell` is the DankMaterialShell lock screen, included only when that
        desktop is enabled — the service does not exist otherwise, and listing it
        anyway would conjure an orphan PAM stack.
      '';
    };

    seahorse.enable = mkOption {
      type = bool;
      default = true;
      description = "Install Seahorse, the GNOME Keyring GUI.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    services.gnome.gnome-keyring.enable = mkDefault true;
    programs.seahorse.enable = mkDefault cfg.seahorse.enable;
    security.pam.services = pamServices;
  };
}
