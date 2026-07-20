# itera's security-key (FIDO2/U2F) battery.
#
# Lets a hardware security key (YubiKey and other FIDO2/U2F tokens) authenticate
# you — including *at login*. Two halves:
#
#   1. Device support: udev rules for hotplug FIDO2/YubiKey access (libfido2 +
#      yubikey-personalization), the pcscd smartcard daemon (so the key also works
#      as a GPG/PIV/SSH smartcard), and `ykman` to manage the key.
#   2. PAM: `security.pam.u2f` wired into every PAM service (login, greetd, sudo,
#      polkit-1, …) as an *additional* factor. The control defaults to `sufficient`
#      — "key OR password": tapping a registered key logs you in, and if the key is
#      absent or unregistered PAM simply falls through to the password prompt, so
#      nobody is locked out. Flip `control = "required"` for true 2FA (key AND
#      password) — only do this once you have a backup key enrolled.
#
# Enrollment is a one-time manual step per user (there is no declarative key
# registry): run `pamu2fcfg >> ~/.config/Yubico/u2f_keys` with the key inserted.
# That path lives under ~/.config, which itera's impermanence layer already
# persists, so the mapping survives the wiped root. Point `authFile` at a central
# file instead if you prefer a system-wide registry.
#
# Desktop integration: when DankMaterialShell is on, its lock screen is told to
# accept the key (`enableU2f`), and its greeter's key-auth UI is enabled so the key
# also works at the graphical login. DMS gates the actual prompt on a key being
# present/ready, so these are harmless on a machine without one.
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
    nullOr
    path
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

  # A minimal greeter settings.json that turns on the greeter's key-auth UI. The
  # DMS greeter only surfaces key auth when its own settings enable it AND the
  # greetd PAM stack carries pam_u2f (which the `security.pam.u2f` wiring below
  # provides). writeTextDir keeps the basename `settings.json` so the greeter's
  # preStart copies it into /var/lib/dms-greeter under the name it reads.
  greeterSettings = pkgs.writeTextDir "settings.json" (
    builtins.toJSON {
      greeterEnableU2f = true;
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

    # Enable the greeter's key-auth UI so the key works at the graphical login.
    (mkIf (dmsCfg.enable && dmsCfg.greeter.enable) {
      programs.dms-greeter.configFiles = [
        "${greeterSettings}/settings.json"
      ];
    })
  ]);
}
