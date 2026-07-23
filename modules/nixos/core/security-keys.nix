# itera's security-key (FIDO2/U2F) battery.
#
# Lets a hardware security key (YubiKey and other FIDO2/U2F tokens) authenticate
# you — but, like the fingerprint battery, deliberately NOT at the initial login.
# The rule itera implements is: the key works *after* you are logged in (the lock
# screen and in-session privilege prompts — sudo, polkit) but never *to* log in
# (neither a TTY `login` nor the graphical greeter). Two halves:
#
#   1. Device support: udev rules for hotplug FIDO2/YubiKey access (libfido2 +
#      yubikey-personalization), the pcscd smartcard daemon (so the key also works
#      as a GPG/PIV/SSH smartcard), and `ykman` to manage the key.
#   2. PAM: `security.pam.u2f` wired in as an *additional* factor. nixpkgs would
#      otherwise apply it to EVERY PAM service (login, greetd, sudo, polkit-1, …);
#      we explicitly set `u2f.enable = false` on the login-surface services
#      (`loginServices`, default `login` + `greetd`) to keep the key off the real
#      login, exactly as the fingerprint battery does with `fprintAuth`. Everywhere
#      else the control defaults to `sufficient` — "key OR password": tapping a
#      registered key logs you in, and if the key is absent or unregistered PAM
#      falls through to the password prompt, so nobody is locked out. Flip
#      `control = "required"` for true 2FA (key AND password) — only do this once
#      you have a backup key enrolled.
#
# Why keep it off the initial login? With pam_u2f in the greetd stack the greeter
# waits on / cues for a key before it will accept the typed password — you'd have to
# tap a key or click Login instead of just pressing Enter. Confining the key to
# post-login surfaces makes password login on the greeter immediate again.
#
# Enrollment is a one-time manual step per user (there is no declarative key
# registry): run `pamu2fcfg >> ~/.config/Yubico/u2f_keys` with the key inserted.
# That path lives under ~/.config, which itera's impermanence layer already
# persists, so the mapping survives the wiped root. Point `authFile` at a central
# file instead if you prefer a system-wide registry.
#
# Desktop integration: when DankMaterialShell is on, its lock screen is told to
# accept the key (`enableU2f`). The greeter's key-auth UI is left OFF (the greeter
# is a login surface), so the graphical login is password-only and submits on Enter.
# Remove `greetd` from `loginServices` to opt the key back into the greeter — that
# re-enables both the greetd pam_u2f factor and the greeter's key-auth UI.
#
# Opt-out like the other core batteries: gated on the master `itera.enable` with
# `mkDefault` values, so it is on by default yet fully overridable. It is safe on
# by default because pam_u2f is only an *additional* `sufficient` factor — password
# login is unaffected on a machine with no key.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types)
    bool
    enum
    listOf
    nullOr
    path
    str
    ;

  cfg = config.itera.securityKeys;
  dmsCfg = config.itera.desktop.dankMaterialShell;

  # Map the pam_u2f control to DMS's lock-screen u2f mode: "sufficient" (key OR
  # password) → "or"; "required" (key AND password / 2FA) → "and".
  u2fMode = if cfg.control == "required" then "and" else "or";

  # pam_u2f settings. `cue` prints the "insert/tap your key" prompt during auth;
  # `authfile` is only set when a central file is requested (else pam_u2f uses its
  # per-user default, ~/.config/Yubico/u2f_keys).
  u2fSettings = {
    cue = mkDefault true;
  }
  // lib.optionalAttrs (cfg.authFile != null) { authfile = cfg.authFile; };

  # Disable pam_u2f on each login-surface service, mirroring the fingerprint
  # battery. nixpkgs defaults each service's `u2f.enable` to `security.pam.u2f.enable`
  # (true here), so these explicit `false`s are what keep the key off the initial
  # login — otherwise the greeter waits on / cues for a key before accepting the
  # typed password.
  loginPamServices = builtins.listToAttrs (
    map (name: {
      inherit name;
      value.u2f.enable = mkDefault false;
    }) cfg.loginServices
  );

  # The greeter surfaces its key-auth UI only when `greetd` is NOT a login surface
  # — i.e. only when the key has been explicitly opted back into the login. Keeping
  # it in step with the greetd pam_u2f factor above avoids showing a key prompt the
  # greetd PAM stack would reject anyway.
  greeterU2fEnabled = !(builtins.elem "greetd" cfg.loginServices);

  # A minimal greeter settings.json that drives the greeter's key-auth UI. The DMS
  # greeter only surfaces key auth when its own settings enable it AND the greetd
  # PAM stack carries pam_u2f. writeTextDir keeps the basename `settings.json` so
  # the greeter's preStart copies it into /var/lib/dms-greeter under the name it
  # reads.
  greeterSettings = pkgs.writeTextDir "settings.json" (
    builtins.toJSON {
      greeterEnableU2f = greeterU2fEnabled;
    }
  );
in
{
  options.itera.securityKeys = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable hardware security key (FIDO2/U2F, e.g. YubiKey) support: device
        udev rules, the pcscd smartcard daemon, and `security.pam.u2f` as an
        additional login/sudo factor. On by default whenever {option}`itera.enable`
        is set; set to `false` to opt out.
      '';
    };

    loginServices = mkOption {
      type = listOf str;
      default = [
        "login"
        "greetd"
      ];
      description = ''
        PAM services that are the *initial-login* surface, on which pam_u2f is
        explicitly disabled (so a security key can never log you in, and the greeter
        accepts the typed password immediately instead of waiting on / cueing for a
        key). The default covers TTY/console login and the graphical greeter. Every
        other service keeps the key as an additional factor, so sudo/polkit still
        accept it in-session. Removing `greetd` from this list opts the key back into
        the graphical login (re-enabling both the greetd pam_u2f factor and the
        greeter's key-auth UI).
      '';
    };

    control = mkOption {
      type = enum [
        "sufficient"
        "required"
      ];
      default = "sufficient";
      description = ''
        The PAM control for pam_u2f.

        - `"sufficient"` (default): *key OR password* — a registered key logs you
          in on its own, and PAM falls through to the password when the key is
          absent, so a lost key never locks you out.
        - `"required"`: *key AND password* (true two-factor). Only choose this once
          you have enrolled a backup key, or losing the key locks you out.
      '';
    };

    authFile = mkOption {
      type = nullOr path;
      default = null;
      example = "/etc/u2f-mappings";
      description = ''
        Override pam_u2f's key-mapping file. `null` (default) uses the per-user
        {file}`~/.config/Yubico/u2f_keys` (persisted by itera's impermanence
        layer). Set a path (e.g. {file}`/etc/u2f-mappings`) to use one central,
        root-owned registry instead — generate entries with {command}`pamu2fcfg`.
      '';
    };

    pcscd = mkOption {
      type = bool;
      default = true;
      description = ''
        Run the pcscd smartcard daemon so the key also works as a GPG/PIV/SSH
        smartcard (CCID). Independent of the FIDO2/U2F PAM path.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) (mkMerge [
    {
      # PAM: pam_u2f as an additional factor across all services (login, greetd,
      # sudo, polkit-1, …). `control` decides key-OR-password vs key-AND-password.
      # Enabling this also adds pkgs.pam_u2f (which ships `pamu2fcfg`) to the system.
      security.pam.u2f = {
        enable = mkDefault true;
        control = mkDefault cfg.control;
        settings = u2fSettings;
      };

      # Keep the key off the initial-login PAM stacks (greetd, login) so the greeter
      # submits the typed password on Enter instead of waiting on / cueing for a key.
      # The lock screen and sudo/polkit still accept the key (see header).
      security.pam.services = loginPamServices;

      # Smartcard daemon for GPG/PIV/SSH use of the key.
      services.pcscd.enable = mkDefault cfg.pcscd;

      # Hotplug device access: libfido2 ships 70-u2f.rules (FIDO2/U2F over hidraw)
      # and yubikey-personalization ships 69-yubikey.rules (YubiKey OTP/CCID).
      services.udev.packages = [
        pkgs.libfido2
        pkgs.yubikey-personalization
      ];

      # `ykman` for inspecting/configuring the key.
      environment.systemPackages = [ pkgs.yubikey-manager ];
    }

    # Tell the DMS lock screen to accept the key. DMS's settings are a flat
    # camelCase passthrough; these are real keys in its schema. Gated on the
    # desktop battery so we don't publish DMS settings when DMS is off.
    (mkIf dmsCfg.enable {
      itera.programs.dankMaterialShell.settings = {
        enableU2f = mkDefault true;
        u2fMode = mkDefault u2fMode;
      };
    })

    # Publish the greeter's key-auth setting. Off by default (the greeter is a login
    # surface); turns on only if `greetd` is removed from `loginServices`. Pushed
    # explicitly either way so the greeter's stored settings.json tracks the intent.
    (mkIf (dmsCfg.enable && dmsCfg.greeter.enable) {
      programs.dms-greeter.configFiles = [
        "${greeterSettings}/settings.json"
      ];
    })
  ]);
}
