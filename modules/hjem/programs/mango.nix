# itera's mango user-config battery (home layer).
#
# The system battery `itera.desktop.mango` installs the compositor and registers
# its session; this hjem battery writes the per-user
# {file}`$XDG_CONFIG_HOME/mango/config.conf` that actually makes the desktop
# usable — most importantly the autostart lines that launch DankMaterialShell
# inside the session.
#
# Why autostart `dms` here rather than via DMS's systemd user service: a bare
# wlroots compositor launched by greetd does not bring up
# {file}`graphical-session.target` on its own, so the DMS systemd unit would
# never start. mango runs `exec-once=` commands on startup and `dms` is on the
# system PATH, so spawning it directly is the reliable path.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`), so sinks
# like `xdg.config.files` are written unprefixed and `osConfig` / `pkgs` are
# available as module args. Enable tracks the system toggle by default, so
# turning on `itera.desktop.mango` is enough — no separate opt-in needed.
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool lines;

  cfg = config.itera.programs.mango;

  # itera's opinionated startup: refresh the D-Bus/systemd user environment (so
  # portals and user services see WAYLAND_DISPLAY etc.) then launch the shell.
  autostartConfig = ''
    exec-once=${pkgs.dbus}/bin/dbus-update-activation-environment --all
    exec-once=dms run
  '';

  configText = lib.concatStringsSep "\n" (
    lib.optional cfg.autostart autostartConfig ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
  );
in
{
  options.itera.programs.mango = {
    enable =
      mkEnableOption "itera's mango user configuration"
      # Follow the system compositor toggle by default: enabling
      # `itera.desktop.mango` is enough to get the matching home config.
      // {
        default = osConfig.itera.desktop.mango.enable or false;
        defaultText = lib.literalExpression "osConfig.itera.desktop.mango.enable";
      };

    autostart = mkOption {
      type = bool;
      default = true;
      description = ''
        Inject itera's default `exec-once` autostart into
        {file}`mango/config.conf`: refresh the D-Bus/systemd user environment and
        launch DankMaterialShell (`dms run`). Turn off to manage startup yourself
        via {option}`itera.programs.mango.extraConfig`.
      '';
    };

    extraConfig = mkOption {
      type = lines;
      default = "";
      example = ''
        # SUPER+Return opens a terminal
        bind=SUPER,Return,spawn,foot
      '';
      description = ''
        Extra lines appended verbatim to {file}`$XDG_CONFIG_HOME/mango/config.conf`
        (keybinds, window rules, `env=` lines, further `exec-once=`, …). See the
        mango docs for the configuration syntax.
      '';
    };
  };

  config = mkIf cfg.enable {
    xdg.config.files."mango/config.conf" = mkIf (configText != "") {
      source = pkgs.writeText "mango-config.conf" (configText + "\n");
    };
  };
}
