# itera's screen-sharing battery (xdg-desktop-portal-wlr source picker).
#
# The mango module brings up the portal stack (xdg-desktop-portal + the wlr and gtk
# backends, with ScreenCast/Screenshot routed to wlr), but it leaves
# xdg-desktop-portal-wlr's own config EMPTY — `xdg.portal.wlr.settings` is `{ }`, so
# nixpkgs generates a zero-byte ini. That is not a cosmetic gap: xdpw cannot start a
# screencast until something picks a source, and with no `chooser_cmd` it falls back
# to a hardcoded cascade (`slurp`, then wmenu/wofi/rofi/bemenu/mew/fuzzel). `slurp`
# is present — nixpkgs' xdpw wrapper puts slurp and grim on its PATH — but it is a
# bare crosshair with no prompt, so it reads as "nothing happened"; dismiss it and
# xdpw walks six dmenu programs itera does not ship and gives up:
#
#   /bin/sh: line 1: wmenu: command not found
#   [ERROR] - wlroots: no output found
#
# With more than one output there is no auto-pick fallback either, so every share
# request died there. This battery pins the picker instead of leaving it to that
# cascade, and points it at DankMaterialShell — the shell itera already ships —
# rather than adding a launcher DMS exists to replace.
#
# How the picker works (see pkgs/dms-screencast-chooser for the other half): xdpw
# runs `chooser_cmd` in `dmenu` mode, piping one label per line ("Monitor: eDP-1",
# "Window: …") and expecting exactly one of those lines back on stdout. The wrapper
# below drops the list in $XDG_RUNTIME_DIR, opens the DMS launcher on the plugin's
# `#share` trigger, and waits for the plugin to write the chosen label back.
#
# Window sharing comes free from that: mango creates ext-image-copy-capture-v1 and
# ext-foreign-toplevel-list-v1, and xdpw 0.8.4 offers `Window:` labels next to
# `Monitor:` ones — a dmenu-mode chooser surfaces both, where slurp could only ever
# return a monitor.
#
# The slurp fallback is deliberate, not belt-and-braces: if DMS is not running (a
# crashed shell, a `dms restart` mid-call) the IPC call fails, and falling back keeps
# screen sharing working instead of failing the request outright. It costs nothing —
# slurp is already a direct dependency of the xdpw derivation. Its `Monitor: %o`
# output matches xdpw's own label format, so the round-trip comparison still holds.
#
# No system state to persist under impermanence — the handoff files live in
# $XDG_RUNTIME_DIR (tmpfs, cleared per boot), same as the other desktop batteries.
#
# Gated on `itera.enable && cfg.enable && itera.desktop.mango.enable`: on by default
# with the desktop (opt-out, like the clipboard/editor batteries), but inert on a
# headless host, where there is no portal to configure.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    bool
    ints
    nullOr
    str
    ;

  cfg = config.itera.desktop.screencast;

  # mango can be enabled without the shell battery (it is DMS that pulls mango in,
  # not the other way round). Without DMS there is no launcher to hand off to, so the
  # picker degrades to slurp rather than dragging the whole shell into the closure
  # for an IPC call that would always fail.
  dmsEnabled = config.itera.desktop.dankMaterialShell.enable;

  # The `dms` CLI, from whatever package the shell battery installed.
  dmsPackage = config.programs.dank-material-shell.package;

  # xdpw's own label format for an output, which the DMS fallback path and the
  # slurp-only default both have to reproduce exactly: whatever a chooser prints is
  # compared against the offered labels with strcmp.
  slurpChooser = "${pkgs.slurp}/bin/slurp -f 'Monitor: %o' -or";

  # What xdpw actually execs. It runs `chooser_cmd` through `/bin/sh -c` with only
  # the xdpw wrapper's own PATH (slurp + grim, nothing else), so every tool this
  # needs has to arrive through runtimeInputs and an absolute path.
  chooser = pkgs.writeShellApplication {
    name = "itera-screencast-chooser";
    runtimeInputs = [
      dmsPackage
      pkgs.coreutils
      pkgs.slurp
    ];
    text = ''
      dir="''${XDG_RUNTIME_DIR:-/tmp}/itera-screencast-chooser"
      mkdir -p "$dir"

      # A stale choice from an abandoned request would otherwise be read as this
      # request's answer, silently sharing the wrong screen.
      rm -f "$dir/choice" "$dir/choice.tmp"

      # xdpw pipes the candidate labels on stdin in dmenu mode. The plugin renders
      # exactly these, and whatever comes back must strcmp-match one of them.
      cat > "$dir/sources"

      cleanup() {
        rm -f "$dir/sources" "$dir/choice" "$dir/choice.tmp"
      }
      trap cleanup EXIT

      # Hand off to the DMS launcher (documented IPC: `spotlight openQuery` opens it
      # with the query pre-filled). The trailing space matters — it puts the launcher
      # past the `#share` trigger and straight into the plugin's item list.
      if dms ipc call spotlight openQuery '#share ' > /dev/null 2>&1; then
        # Poll rather than block on a FIFO: a FIFO write from the plugin would hang
        # forever if this side had already timed out, leaking a process per cancel.
        deadline=$(( ${toString cfg.timeoutSeconds} * 10 ))
        for _ in $(seq 1 "$deadline"); do
          if [ -f "$dir/choice" ]; then
            cat "$dir/choice"
            exit 0
          fi
          sleep 0.1
        done

        # Nothing picked before the deadline. Printing nothing is how a chooser tells
        # xdpw the user declined.
        exit 0
      fi

      # DMS is not answering — fall back to xdpw's own picker so a share request
      # still has some way to succeed. Monitors only; slurp cannot name a window.
      # Not `exec`, so the EXIT trap still clears the handoff files.
      ${slurpChooser}
    '';
  };

  defaultChooserCommand =
    if dmsEnabled then "${chooser}/bin/itera-screencast-chooser" else slurpChooser;
in
{
  options.itera.desktop.screencast = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Configure the wlroots portal's screencast source picker so screen sharing
        works. Without it xdg-desktop-portal-wlr has no `chooser_cmd` and every
        request fails with `no output found`. Ships a DankMaterialShell launcher
        plugin (trigger `#share`) that lists the monitors and windows the portal
        offers, so apps like Teams, Zoom and Vivaldi can share either. On by default
        whenever the mango desktop is enabled; set to `false` to opt out (or to wire
        your own chooser). Inert on a headless host.
      '';
    };

    chooserCommand = mkOption {
      type = str;
      default = defaultChooserCommand;
      defaultText = lib.literalExpression "the DankMaterialShell picker when the shell battery is on (slurp fallback built in), otherwise slurp alone";
      example = lib.literalExpression ''"''${pkgs.fuzzel}/bin/fuzzel -d -l 10 -p 'Share: '"'';
      description = ''
        Command xdg-desktop-portal-wlr runs to pick a screencast source, as
        `chooser_cmd`. It is run through {command}`/bin/sh -c` with only the portal's
        own PATH, so give an absolute path. Paired with
        {option}`itera.desktop.screencast.chooserType`: under `dmenu` the command
        receives the candidate labels on stdin and must echo exactly one of them back
        on stdout; printing nothing means the user declined.
      '';
    };

    chooserType = mkOption {
      type = str;
      default = if dmsEnabled then "dmenu" else "simple";
      defaultText = lib.literalExpression ''"dmenu" when the DankMaterialShell battery is on, else "simple" (what a bare slurp needs)'';
      example = "simple";
      description = ''
        `chooser_type` for xdg-desktop-portal-wlr. `dmenu` pipes the candidate labels
        to {option}`itera.desktop.screencast.chooserCommand` on stdin — the only mode
        that can offer `Window:` sources as well as `Monitor:` ones. `simple` pipes
        nothing and leaves the command to discover sources itself (what a bare
        {command}`slurp` needs). See {manpage}`xdg-desktop-portal-wlr(5)`.
      '';
    };

    maxFps = mkOption {
      type = nullOr ints.positive;
      default = null;
      example = 30;
      description = ''
        Cap the screencast frame rate. `null` (default) leaves it uncapped, so
        capture runs at the output's refresh rate. Lowering it trades smoothness for
        CPU on a high-refresh display.
      '';
    };

    timeoutSeconds = mkOption {
      type = ints.positive;
      default = 60;
      description = ''
        How long the picker waits for a choice before reporting that the user
        declined. Only applies to the bundled DankMaterialShell chooser; a custom
        {option}`itera.desktop.screencast.chooserCommand` sets its own policy.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable && config.itera.desktop.mango.enable) {
    # Fill in the portal backend's settings — do NOT re-declare the portal wiring
    # itself. `xdg.portal.wlr.enable` is already mkDefault true from the upstream
    # mango module; this only populates the ini it generates, which is empty today.
    xdg.portal.wlr.settings.screencast = {
      chooser_type = mkDefault cfg.chooserType;
      chooser_cmd = mkDefault cfg.chooserCommand;
    }
    // lib.optionalAttrs (cfg.maxFps != null) {
      max_fps = mkDefault cfg.maxFps;
    };

    # The chooser reaches xdpw as an absolute store path, so it does not need to be
    # on PATH to work — but a screencast picker that cannot be run by hand is
    # miserable to debug, since the only other way to exercise it is to start a real
    # call. Ship it so the source list can be replayed directly:
    #
    #   printf 'Monitor: eDP-1\nMonitor: DP-10\n' | itera-screencast-chooser
    #
    # Only when it is actually the configured chooser — a consumer who points
    # `chooserCommand` elsewhere gets no stray binary.
    environment.systemPackages = lib.optional (cfg.chooserCommand == defaultChooserCommand) chooser;

    # The picker itself. Registered like the ipIndicator plugin next door, so it is
    # installed AND enabled declaratively — no Settings → Plugins → Scan step.
    itera.programs.dankMaterialShell.plugins = mkIf dmsEnabled {
      screencastChooser.src = mkDefault ../../../pkgs/dms-screencast-chooser;
    };

    # These settings only reach xdpw through nixpkgs' wlr portal module, which is
    # what rewrites the service's `--config=`. If something turned it off, the ini
    # silently reverts to xdpw's broken default cascade.
    warnings = lib.optional (!config.xdg.portal.wlr.enable) ''
      itera.desktop.screencast is enabled but xdg.portal.wlr.enable is off — the
      screencast chooser settings will not be written, and screen sharing will fail
      with "no output found".
    '';
  };
}
