# itera's DankMaterialShell (DMS) battery.
#
# A thin, opinionated wrapper over DMS's two NixOS modules (bundled by
# `modules/nixos/default.nix`): the shell (`programs.dank-material-shell`) and the
# greeter (`programs.dank-material-shell.greeter`). DMS is a Quickshell-based
# Wayland desktop shell; this battery stands up a complete, login-to-desktop
# experience on top of the mango compositor.
#
# It pulls in the mango battery (`itera.desktop.mango`) — the shell is useless
# without a compositor — and, unless you opt out, turns on DMS's own greetd
# greeter rendered under mango. Login lands in the `mango` session, whose
# user-side autostart (`itera.programs.mango`, the hjem battery) launches `dms`.
#
# Opt-OUT: on automatically with `itera.enable` (following the same shape as
# `itera.hardening`), gated on `itera.enable && cfg.enable` with `mkDefault`
# values so it comes along by default but every knob is overridable. Set
# `itera.desktop.dankMaterialShell.enable = false` to drop the desktop while
# keeping the rest of itera. DMS's feature toggles (`enableSystemMonitoring`,
# `enableDynamicTheming`, …) keep their upstream defaults and stay reachable
# through the native `programs.dank-material-shell.*` options, since the upstream
# module is bundled.
#
# Greeter wiring note: the DMS greeter enables greetd, which (via the nixpkgs
# greetd module) already creates the `greeter` system user and defaults
# `services.greetd.settings.default_session.user` to `"greeter"` — so we do not
# declare that user here.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) bool attrsOf anything;

  cfg = config.itera.desktop.dankMaterialShell;
in
{
  options.itera.desktop.dankMaterialShell = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install the DankMaterialShell desktop (on the mango compositor). On by
        default whenever {option}`itera.enable` is set; set this to `false` to opt
        out of the desktop while keeping the rest of itera.
      '';
    };

    greeter.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Use DankMaterialShell's own greetd greeter (rendered under mango) as the
        login manager. On by default whenever the desktop is enabled; set this to
        `false` to install the shell without a display manager (you then arrange
        login yourself).
      '';
    };

    settings = mkOption {
      type = attrsOf anything;
      default = { };
      example = {
        currentThemeName = "blue";
        cornerRadius = 12;
        use24HourClock = true;
      };
      description = ''
        System-wide DankMaterialShell settings applied to *every* user, written
        (by the {option}`hjem.users.<name>.itera.programs.dankMaterialShell`
        battery) to {file}`~/.config/DankMaterialShell/settings.json`. This is the
        single source of truth for the "default settings for all users" — each
        user inherits it and overrides individual keys under
        {option}`hjem.users.<name>.itera.programs.dankMaterialShell.settings`.

        The schema is DMS's own flat camelCase settings object; itera only sets a
        small curated subset here (`mkDefault`, so overridable per key). Keys you
        do not set fall back to DMS's own runtime defaults.
      '';
    };

    pluginSettings = mkOption {
      type = attrsOf anything;
      default = { };
      description = ''
        System-wide DankMaterialShell external plugin settings, written to
        {file}`~/.config/DankMaterialShell/plugin_settings.json` for every user.
        Same override model as {option}`itera.desktop.dankMaterialShell.settings`.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) (mkMerge [
    {
      # The shell needs a compositor — pull mango in.
      itera.desktop.mango.enable = mkDefault true;

      programs.dank-material-shell.enable = mkDefault true;

      # itera's curated system-wide DMS defaults. Kept intentionally small —
      # pin the settings schema version DMS expects and a couple of opinionated
      # choices; everything else is left to DMS's own runtime defaults. Each key
      # is mkDefault, so a consumer overrides individual keys (per-user overrides
      # then merge on top in the hjem battery). No null-valued keys (toJSON would
      # emit `null`, which DMS may reject).
      itera.desktop.dankMaterialShell.settings = {
        configVersion = mkDefault 11;
        use24HourClock = mkDefault true;
        # Dark mode by default: don't follow the desktop portal's color-scheme
        # (which reports "no preference" on a fresh session and would flip DMS to
        # light). With portal sync off, DMS uses its stored isLightMode, which
        # defaults to false (dark). Users can still toggle light in the DMS UI —
        # that writes ~/.local/state/DankMaterialShell/session.json, which itera
        # does not manage.
        syncModeWithPortal = mkDefault false;
      };
    }

    (mkIf cfg.greeter.enable {
      programs.dank-material-shell.greeter = {
        enable = mkDefault true;
        # `compositor.name` has no upstream default; render the greeter under mango.
        compositor.name = mkDefault "mango";
      };

      # Default the post-login session picker to the mango session that the mango
      # module registers with the display manager.
      services.displayManager.defaultSession = mkDefault "mango";
    })
  ]);
}
