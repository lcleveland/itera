# itera's video-player battery (mpv) — on the desktop AND inside the terminal.
#
# Native NixOS/nixpkgs feature (no flake input): itera shipped no way to play a
# video at all. Double-clicking a `.mkv` in Nemo found no handler, and a stream
# URL had nothing behind it but the browser. This battery installs mpv — small,
# Wayland-native, and backed by ffmpeg, so it plays essentially any container or
# codec without a plugin hunt — and makes it the session's default handler for
# the common video types and stream schemes.
#
# URL playback needs no extra wiring: nixpkgs' mpv wrapper is built with
# `youtubeSupport = true`, which bakes yt-dlp into mpv's own PATH, so
# `mpv <url>` resolves streams out of the box.
#
# Hardware decoding ({option}`hardwareDecoding`) is OPT-IN, and that is the whole
# point of the option. mpv's manual is explicit: "Hardware decoding is not enabled
# by default, to keep the out-of-the-box configuration as reliable as possible" —
# and it goes on to name distributions that ship an /etc/mpv/mpv.conf forcing it
# on as getting this wrong. This battery shipped exactly that mistake
# (`hwdec=auto-safe`) and it produced visibly corrupt video on a hybrid
# AMD+NVIDIA desktop: `auto` takes the first whitelisted method that initialises,
# which there was Vulkan video decode on the discrete GPU. The DECODE was fine —
# frames copied back with `vulkan-copy` and `vaapi-copy` came out bit-identical
# to software — so what breaks is the zero-copy interop between the decoding and
# the displaying device. That is exactly the host-specific minefield mpv is
# warning about, and it is not something a framework can decide for a host it
# cannot see.
#
# Turning it on writes `hwdec=auto` and, on a host whose facter report shows an
# Intel GPU, installs `intel-media-driver` — the VA-API driver nothing else in
# itera provides (mesa covers AMD, the NVIDIA battery covers NVIDIA) — rather
# than advertising hardware decoding with nothing behind it. Test before relying
# on it: mpv binds Ctrl+h to toggle hwdec at runtime, which answers "is this host
# one of the good ones?" in one keystroke.
#
# The IN-TERMINAL half ({option}`terminal.enable`) ships `mpv-term`
# (cli/mpv-term.sh): the same mpv, rendering into the terminal you are sitting
# in. itera's terminal battery ships WezTerm, which implements the kitty graphics
# protocol — real pixels, not ASCII art — so `mpv-term clip.mkv` plays properly
# in the session's own terminal. The wrapper detects that per-terminal at run
# time (environment allow-list, then the protocol's own capability query) and
# falls back to mpv's true-colour text output anywhere else, so it always plays
# something.
#
# What makes it PLAY rather than stop on the first frame is shared-memory
# transfer: the protocol's default is base64 escape codes through the pty, and a
# video is a new image every frame — measured at ~67 MB/s for a 720p clip in a
# 1600x800 window, which no terminal emulator can absorb. See the script header
# for that, for the SSH case where shm is unavailable, and for why sixel is not
# an option here (nixpkgs builds mpv with `sixelSupport = false`).
#
# {option}`settings` writes {file}`/etc/mpv/mpv.conf` (mpv is built with
# `sysconfdir = /etc`), which mpv reads BEFORE `~/.config/mpv/mpv.conf` — so
# anything set there is a default a user can still override, with no itera wiring
# in $HOME. Nothing is set by default, so by default the file is not written at
# all and mpv behaves exactly as it does out of the box, which is what its manual
# recommends. There is no system state to persist under impermanence either:
# mpv's own state (watch-later positions, `~/.config/mpv`) lives in the curated
# `.config` / `.local/state` home dirs the impermanence battery already persists.
#
# Audio types are deliberately left unclaimed: mpv plays them fine when handed
# one, but itera ships no audio-player battery, and quietly making the video
# player the default for every `audio/*` type is a decision that belongs to one.
#
# No compositor bind either — unlike the terminal or the browser, a player opened
# with no file is an empty window. It is launched from a file or a URL, which is
# what the mime handlers below are for.
#
# Opt-OUT (default ON): set `itera.desktop.videoPlayer.enable = false` to drop it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkPackageOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    attrsOf
    bool
    int
    oneOf
    str
    ;

  cfg = config.itera.desktop.videoPlayer;

  # The `.desktop` id nixpkgs' mpv package installs.
  desktopId = "mpv.desktop";

  # mpv.conf is `key=value` lines, one per option, with flags spelled yes/no
  # rather than true/false.
  renderValue = v: if builtins.isBool v then (if v then "yes" else "no") else toString v;
  mpvConf = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "${k}=${renderValue v}") cfg.settings
  );

  # facter's `graphics_card` entries carry a numeric PCI vendor id; Intel's is
  # 32902 (0x8086). Same detection shape as the NVIDIA one in
  # modules/nixos/core/facter.nix, which reads 4318 (0x10de) from the same list.
  gpus = config.facter.report.hardware.graphics_card or [ ];
  hasIntelGpu = builtins.any (c: (c.vendor.value or null) == 32902) gpus;

  # The in-terminal wrapper. `runtimeInputs` carries the configured player rather
  # than trusting the ambient PATH, so `mpv-term` works from a shell that has no
  # mpv on it (and follows a consumer's `package` override). stty, which the
  # capability query drives the tty with, comes from coreutils.
  #
  # Lazily bound: never forced when `package = null` drops the wrapper below.
  mpvTerm = pkgs.writeShellApplication {
    name = "mpv-term";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
    ];
    text = builtins.readFile ../../../cli/mpv-term.sh;
  };
in
{
  options.itera.desktop.videoPlayer = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install the mpv video player, make it the session's default handler for
        common video types and stream schemes, and ship the in-terminal
        {command}`mpv-term` wrapper. On by default whenever {option}`itera.enable`
        is set; set to `false` to opt out (or to ship your own player).
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # mpv build) while keeping the handler wiring below. It also drops
    # `mpv-term`, which is a wrapper around this package and nothing without it.
    package = mkPackageOption pkgs "mpv" { nullable = true; };

    hardwareDecoding = mkOption {
      type = bool;
      default = false;
      description = ''
        Decode video on the GPU, by defaulting {option}`settings`.`hwdec` to
        `auto`. On a host whose facter report shows an Intel GPU this also
        installs `intel-media-driver`, the VA-API driver nothing else in itera
        provides — AMD gets VA-API from mesa and NVIDIA from
        {option}`itera.nvidia`.

        Off by default, matching mpv itself: whether the GPU decode path renders
        correctly is a property of the host, and on a machine with two GPUs it
        can produce visibly corrupt video even though the decoding is exact (the
        breakage is in the zero-copy handoff to the display device). Turn it on
        once you have checked this host — mpv's Ctrl+h toggles hwdec at runtime —
        and pin a known-good method with `settings.hwdec` if `auto` picks badly.
      '';
    };

    settings = mkOption {
      type = attrsOf (oneOf [
        bool
        int
        str
      ]);
      default = { };
      example = {
        hwdec = "vaapi";
        keep-open = true;
        save-position-on-quit = true;
      };
      description = ''
        Options written to {file}`/etc/mpv/mpv.conf` as `key=value` lines
        (booleans render as `yes`/`no`). mpv reads this file before the user's own
        {file}`~/.config/mpv/mpv.conf`, so anything here is a *default* a user can
        still override. itera sets nothing by default — only
        {option}`hardwareDecoding` adds a key (`hwdec`) — and the file is not
        written at all while this is empty.
      '';
    };

    terminal.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Ship {command}`mpv-term`, which plays video inside the terminal instead of
        in a window. It uses the kitty graphics protocol — real pixels — in
        terminals that implement it, including the WezTerm that
        {option}`itera.desktop.terminal` installs, and falls back to mpv's
        true-colour text output everywhere else. In a terminal it recognises by
        name it also transfers frames through shared memory, without which the
        base64-over-pty default stops the video on its first frame.
        `MPV_TERM_VO=<vo>` overrides the choice for a single run. Set to `false`
        to install the GUI player only.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages =
      lib.optional (cfg.package != null) cfg.package
      ++ lib.optional (cfg.terminal.enable && cfg.package != null) mpvTerm;

    # `mkDefault` so `settings.hwdec = "vaapi"` pins a known-good method for a
    # host without having to turn the switch off and hand-write the line.
    itera.desktop.videoPlayer.settings.hwdec = mkIf cfg.hardwareDecoding (mkDefault "auto");

    # NOT `mkDefault`, deliberately. `extraPackages` is a list, so same-priority
    # definitions concatenate — but NixOS' own nvidia module defines it at NORMAL
    # priority, which drops every `mkDefault` definition outright (itera's own
    # NVIDIA battery already loses its list that way). An `mkDefault` here would
    # therefore vanish on precisely the host that needs both: the hybrid
    # Intel+NVIDIA laptop. At normal priority it concatenates with upstream's
    # instead, and a consumer's own plain definition still merges with it.
    hardware.graphics.extraPackages = mkIf (cfg.hardwareDecoding && hasIntelGpu) [
      pkgs.intel-media-driver
    ];

    # Skipped entirely when `settings` is empty, so opting hardware decoding out
    # leaves no orphan config file behind.
    environment.etc."mpv/mpv.conf" = mkIf (cfg.settings != { }) { text = mpvConf + "\n"; };

    # A focused set of the containers people actually have on disk (like the
    # editor and browser batteries), not mpv.desktop's full ~120-entry list.
    # Anything not named here keeps whatever handler claims it.
    xdg.mime.defaultApplications = {
      "video/mp4" = mkDefault desktopId;
      "video/x-matroska" = mkDefault desktopId;
      "video/webm" = mkDefault desktopId;
      "video/quicktime" = mkDefault desktopId;
      "video/x-msvideo" = mkDefault desktopId;
      "video/mpeg" = mkDefault desktopId;
      "video/x-ms-wmv" = mkDefault desktopId;
      "video/x-flv" = mkDefault desktopId;
      "video/ogg" = mkDefault desktopId;
      "video/3gpp" = mkDefault desktopId;
      "video/mp2t" = mkDefault desktopId;
      "video/x-m4v" = mkDefault desktopId;

      # Stream schemes. The browser battery claims http/https, and nothing on the
      # desktop claimed these — so an `rtsp://` link had no handler at all, even
      # though mpv opens one directly.
      "x-scheme-handler/rtsp" = mkDefault desktopId;
      "x-scheme-handler/rtmp" = mkDefault desktopId;
      "x-scheme-handler/mms" = mkDefault desktopId;
    };
  };
}
