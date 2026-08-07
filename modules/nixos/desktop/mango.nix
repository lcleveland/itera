# itera's mango compositor battery (install / host wiring).
#
# A thin, opinionated wrapper over the mango NixOS module (bundled by
# `modules/nixos/default.nix`). mango is a dwl-based wlroots Wayland compositor;
# enabling this turns it on and — through the upstream module — brings along the
# xdg-desktop-portal wiring (wlr + gtk), polkit, xwayland, and registers a
# `mango` wayland session with the display manager.
#
# Unlike the core-boot batteries, a desktop is NOT part of the opinionated base,
# so this gates on its OWN `enable` (`mkEnableOption`, opt-in) rather than the
# global `itera.enable` — exactly like `itera.disko`.
#
# Scope: this module owns *installation* and the host-level spawn `commands`
# (which sibling batteries — terminal/browser/editor/file-manager — set, and which
# feed the default keybind set). The curated *user-facing* options
# (keybinds/layout/…) are declared once by the curated-program registration
# `modules/programs/mango.nix`, exposed system-wide at `itera.programs.mango.*` and
# per-user at `itera.users.<name>.programs.mango.*`; the hjem battery
# `modules/hjem/programs/mango.nix` renders the merged result into config.conf.
#
# Fine-grained tuning stays reachable through the native `programs.mango.*`
# options, which remain in place because the upstream module is bundled.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    nullOr
    str
    ;

  cfg = config.itera.desktop.mango;
in
{
  options.itera.desktop.mango = {
    enable = mkEnableOption "the mango Wayland compositor";

    commands = {
      terminal = mkOption {
        type = nullOr str;
        default = null;
        example = "foot";
        description = ''
          Command SUPER+t spawns. `null` (default) means itera adds no terminal
          keybind (itera ships no terminal — name one to get the bind).
        '';
      };

      fileBrowser = mkOption {
        type = nullOr str;
        # Follow the file-manager battery: when Nemo is installed
        # (`itera.desktop.fileManager`, on by default) SUPER+f opens it. Name a
        # different command here to override, or `null` to drop the bind.
        default =
          if
            config.itera.enable
            && config.itera.desktop.fileManager.enable
            && config.itera.desktop.fileManager.package != null
          then
            "nemo"
          else
            null;
        defaultText = lib.literalExpression ''"nemo" when itera.desktop.fileManager is enabled, else null'';
        example = "foot -e yazi";
        description = ''
          Command SUPER+f spawns. Defaults to `nemo` when the file-manager
          battery ({option}`itera.desktop.fileManager`) is enabled; `null` adds no
          file-browser keybind.
        '';
      };

      browser = mkOption {
        type = nullOr str;
        default = null;
        example = "firefox";
        description = ''
          Command SUPER+b spawns. `null` (default) adds no browser keybind
          (name one, or enable `itera.desktop.browser`, to get the bind).
        '';
      };

      editor = mkOption {
        type = nullOr str;
        default = null;
        example = "zeditor";
        description = ''
          Command SUPER+e spawns. `null` (default) adds no editor keybind; the
          editor battery ({option}`itera.desktop.editor`, on by default) sets this
          to `zeditor`. Name a different command here to override, or `null` to
          drop the bind.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    programs.mango.enable = mkDefault true;

    # Tools the default media/brightness keybinds shell out to (`pactl` already
    # comes with the audio server). Without these on PATH the XF86 keys are
    # silent no-ops. brightnessctl needs the `video` group, which the user
    # battery already grants (`core/users.nix`).
    environment.systemPackages = [
      pkgs.playerctl
      pkgs.brightnessctl
    ];

    # GTK apps persist their settings through dconf; enable it now that a
    # graphical session exists.
    programs.dconf.enable = mkDefault true;

    # Session target. mango is a bare wlroots compositor: greetd execs it
    # directly, so nothing brings up `graphical-session.target` in the systemd
    # user manager. That used to be merely untidy, but xdg-desktop-portal 1.22
    # added `Requisite=graphical-session.target` to its user unit (upstream
    # #1830, "launch after the graphical session target"), so with the target
    # dead the portal cannot start at all — taking file pickers, screencast and
    # the `org.freedesktop.appearance` color-scheme (itera's dark default, read
    # by Zed and every Flatpak app) down with it.
    #
    # This mirrors the `mango-session.target` that mango's own home-manager
    # module defines — itera uses hjem, not home-manager, so the NixOS half
    # declares it instead. `bindsTo` is what pulls `graphical-session.target`
    # up: the hjem battery's autostart starts *this* target, and the binding
    # activates the real one (and tears this one down with it). Starting
    # `graphical-session.target` directly would work too, but keeping mango's
    # unit name means anything written against upstream's layout still applies.
    systemd.user.targets.mango-session = {
      description = "mango compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };
  };
}
