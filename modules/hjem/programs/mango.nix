# itera's mango user-config renderer (home layer).
#
# The system battery `itera.desktop.mango` installs the compositor and registers
# its session; the curated-program registration `modules/programs/mango.nix`
# declares the tunable options (system-wide `itera.programs.mango.*` + per-user
# `itera.users.<name>.programs.mango.*`). THIS battery is the renderer: it reads
# the resolved settings through the registration's `resolve` and writes the per-user
# {file}`$XDG_CONFIG_HOME/mango/config.conf` — most importantly the autostart lines
# that launch DankMaterialShell inside the session.
#
# A bare wlroots compositor launched by greetd brings up no systemd user session
# of its own, so this battery's first autostart entry does it: it exports the
# session environment and starts `mango-session.target`, which is bound to
# {file}`graphical-session.target` (see `modules/nixos/desktop/mango.nix`).
# xdg-desktop-portal 1.22+ refuses to start without that target, so this is what
# keeps portals — file pickers, screencast, the color-scheme preference — alive.
#
# `dms` itself runs as DMS's systemd user service, wanted by
# `mango-session.target` (set up by the desktop battery), so starting the target
# starts the shell and a crash restarts it. With that service turned off the shell
# falls back to a plain `exec_once=`.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`), so sinks
# like `xdg.config.files` are written unprefixed, `osConfig`/`pkgs`/`iteraLib` are
# module args, and `name` is the username. This battery declares NO options — the
# schema lives in the registration; enablement follows the system compositor toggle.
{
  lib,
  pkgs,
  iteraLib,
  osConfig ? null,
  name,
  programs,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.mango.enable or false;

  # System-wide defaults (itera.programs.mango) merged with this user's
  # overrides, binds through the registration's merge hooks. A plain user (no
  # `itera.users.<name>` entry) resolves to the defaults.
  cfg = programs.mango.resolve osConfig name;
  look = iteraLib.look.resolve osConfig name;

  # itera's opinionated startup: bring the systemd/D-Bus user session up (so
  # portals and user services see WAYLAND_DISPLAY etc. and can actually start),
  # then launch the shell.
  #
  # The session bring-up is one script rather than three `exec_once=` lines
  # because mango spawns each `exec_once` asynchronously: the environment must
  # be in place *before* the target activates, or the units it pulls in inherit
  # an empty one. mango does export the session variables itself these days
  # (`set_activation_env()` in mango.c, issued just before the exec_once list),
  # but it too is an async spawn and its fixed variable list omits NixOS's
  # `NIXOS_OZONE_WL`, so doing it here keeps the ordering deterministic.
  # `MANGO_INSTANCE_SIGNATURE` matters to DMS: its mango colour template
  # (dms/colors.conf) only renders when the variable names a live socket.
  #
  # `mango-session.target` is declared by the system battery
  # (`modules/nixos/desktop/mango.nix`) and is bound to
  # `graphical-session.target`, so starting it activates the target that
  # xdg-desktop-portal 1.22+ requires. `reset-failed` first, so units left
  # failed by a previous session on this user manager can start again.
  sessionSetup = pkgs.writeShellScript "itera-mango-session-setup" ''
    ${pkgs.dbus}/bin/dbus-update-activation-environment --all
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE NIXOS_OZONE_WL \
      XCURSOR_THEME XCURSOR_SIZE MANGO_INSTANCE_SIGNATURE
    ${pkgs.systemd}/bin/systemctl --user reset-failed
    ${pkgs.systemd}/bin/systemctl --user start mango-session.target
  '';

  # The look's starting cursor, while the cursor battery is on.
  cursorOn = (osConfig.itera.enable or false) && (osConfig.itera.desktop.cursor.enable or false);

  configText = iteraLib.mango.renderConfig {
    settings = cfg;
    inherit look;
    # Keyboard layout: driven by the system `itera.keyboard` battery
    # (services.xserver.xkb), so the session's layout follows the console/greeter.
    xkb = osConfig.services.xserver.xkb or { };
    execOnce = lib.optionals cfg.autostart (
      [ "${sessionSetup}" ]
      # systemd-cat so the shell's output lands in the journal (`journalctl --user -t dms`).
      ++ lib.optional (
        !(osConfig.programs.dank-material-shell.systemd.enable or false)
      ) "${pkgs.systemd}/bin/systemd-cat -t dms dms run"
    );
    cursor =
      if cursorOn then
        {
          name = look.cursor.name.${look.startMode};
          inherit (look.cursor) size;
        }
      else
        null;
    dmsFragments = osConfig.itera.desktop.dankMaterialShell.enable or false;
  };
in
{
  config = mkIf enable {
    xdg.config.files."mango/config.conf" = mkIf (configText != "") {
      # Parsed with `mango -p` at build time (as upstream's home-manager module
      # does): an unknown key (e.g. after an upstream rename, which mango ships
      # without aliases) or a keybind conflict fails the rebuild instead of being
      # skipped at runtime.
      source = iteraLib.mango.validateConfig {
        inherit pkgs;
        mango = osConfig.programs.mango.package;
        text = configText + "\n";
      };
      # Explicit clobber (beyond itera's `hjem.clobberByDefault = true`) so the
      # linker OVERWRITES an existing target instead of leaving it. Two reasons:
      # (1) under itera's impermanence ~/.config is restored from /persist every
      # boot, so a non-clobber file freezes at its first-ever link target; and
      # (2) setting it here changes this entry in smfh's manifest, which forces
      # smfh's diff to treat it as "updated" and re-link it — healing a symlink
      # already stranded on a stale target (e.g. the old `spawn,ghostty` bind)
      # on the next rebuild, which flipping only the global default would not do.
      clobber = true;
    };
  };
}
