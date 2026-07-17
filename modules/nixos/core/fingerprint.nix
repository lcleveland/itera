# itera's fingerprint-reader battery.
#
# Turns on fprintd so a fingerprint can authenticate you — but deliberately NOT at
# the initial login. The rule itera implements is: fingerprint works *after* you
# are logged in (the lock screen and in-session privilege prompts) but never *to*
# log in (neither a TTY `login` nor the graphical greeter).
#
# Why that split is even possible. DankMaterialShell drives both the greeter and
# the lock screen, but they authenticate through different paths:
#
#   - The initial login goes through the SYSTEM PAM stacks — `/etc/pam.d/greetd`
#     (greeter) and `/etc/pam.d/login` (TTY, and the lock screen's *password*
#     fallback). nixpkgs defaults `security.pam.services.<svc>.fprintAuth` to
#     `services.fprintd.enable`, so enabling fprintd would otherwise add fingerprint
#     to EVERY service, including these. We explicitly set `fprintAuth = false` on
#     the login-surface services (`loginServices`) to keep it off the real login.
#   - The lock screen's *fingerprint* path does NOT use /etc/pam.d at all: DMS ships
#     its own self-contained pam_fprintd stack inside the package
#     (`<dms>/share/quickshell/dms/assets/pam/fprint`) and gates it purely on its
#     `enableFprint` setting plus a running fprintd. So enabling fprintd + DMS's
#     `enableFprint` gives fingerprint unlock on the lock screen while the login
#     stacks above stay password/key-only.
#
# Everything NOT in `loginServices` keeps fprintd's default (fingerprint allowed),
# so `sudo` and `polkit-1` get in-session fingerprint for privilege prompts for
# free — matching "usable once you have logged in".
#
# Enrollment is a one-time manual step per user (fprintd has no declarative print
# store): run `fprintd-enroll`. Enrolled prints live in /var/lib/fprint, which
# itera's impermanence layer persists (gated on this battery) so they survive the
# wiped root.
#
# Opt-out like the other core batteries: gated on the master `itera.enable` with
# `mkDefault` values, so it is on by default yet fully overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types)
    bool
    ints
    listOf
    str
    ;

  cfg = config.itera.fingerprint;
  dmsCfg = config.itera.desktop.dankMaterialShell;

  # Disable fprintAuth on each login-surface service. fprintd's per-service default
  # is `true` (once fprintd is enabled), so these explicit `false`s are what keep
  # fingerprint off the initial login.
  loginPamServices = builtins.listToAttrs (
    map (name: {
      inherit name;
      value.fprintAuth = mkDefault false;
    }) cfg.loginServices
  );
in
{
  options.itera.fingerprint = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable fingerprint-reader support (fprintd). Fingerprint authenticates the
        lock screen and in-session privilege prompts (sudo, polkit) but NOT the
        initial login (see {option}`itera.fingerprint.loginServices`). On by default
        whenever {option}`itera.enable` is set; set to `false` to opt out. Enroll a
        finger with {command}`fprintd-enroll`.
      '';
    };

    loginServices = mkOption {
      type = listOf str;
      default = [
        "login"
        "greetd"
      ];
      description = ''
        PAM services that are the *initial-login* surface, on which fingerprint auth
        is explicitly disabled (so a fingerprint can never log you in). The default
        covers TTY/console login and the graphical greeter. Every other service
        keeps fprintd's default, so sudo/polkit still accept a fingerprint in-session.
      '';
    };

    maxTries = mkOption {
      type = ints.positive;
      default = 15;
      description = "Maximum fingerprint attempts on the DankMaterialShell lock screen.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) (mkMerge [
    {
      services.fprintd.enable = mkDefault true;

      # Keep fingerprint off the initial-login PAM stacks (see header). The lock
      # screen's fingerprint path is DMS's own bundled stack, so this does not
      # affect lock-screen unlock.
      security.pam.services = loginPamServices;
    }

    # Tell the DMS lock screen to offer fingerprint unlock. DMS's settings are a
    # flat camelCase passthrough; `enableFprint`/`maxFprintTries` are real schema
    # keys. Gated on the desktop battery so we don't publish DMS settings when DMS
    # is off. The greeter's `greeterEnableFprint` is left at its `false` default —
    # belt-and-suspenders with the `greetd.fprintAuth = false` above.
    (mkIf dmsCfg.enable {
      itera.programs.dankMaterialShell.settings = {
        enableFprint = mkDefault true;
        maxFprintTries = mkDefault cfg.maxTries;
      };
    })
  ]);
}
