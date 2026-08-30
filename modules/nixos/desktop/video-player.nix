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
# Hardware decoding ({option}`hardwareDecoding`, on by default) writes
# `hwdec=auto-safe` into the system mpv config — mpv's own default is `no`, which
# means a 4K stream is decoded on the CPU, dropping frames on a laptop and
# burning battery to do it. `auto-safe` only picks a decoder from the known-good
# list, so it degrades to software rather than to a broken picture. AMD gets
# VA-API from mesa and NVIDIA gets `nvidia-vaapi-driver` from the NVIDIA battery,
# but Intel needs a driver nothing else installs — so when the facter report
# shows an Intel GPU, this battery adds `intel-media-driver` rather than
# advertising hardware decoding with nothing behind it. With no facter report
# there is no detection, and hwdec quietly falls back to software; add
# `hardware.graphics.extraPackages` yourself on such a host.
#
# The IN-TERMINAL half ({option}`terminal.enable`) ships `mpv-term`
# (cli/mpv-term.sh): the same mpv, rendering into the terminal you are sitting
# in. itera's terminal battery ships WezTerm, which implements the kitty graphics
# protocol — real pixels, not ASCII art — so `mpv-term clip.mkv` plays properly
# in the session's own terminal. The wrapper detects that per-terminal at run
# time (environment allow-list, then the protocol's own capability query) and
# falls back to mpv's true-colour text output anywhere else, so it always plays
# something. See the script header for the full story, including why sixel is not
# an option here (nixpkgs builds mpv with `sixelSupport = false`).
#
# The system config lives at {file}`/etc/mpv/mpv.conf` (mpv is built with
# `sysconfdir = /etc`). mpv reads it BEFORE `~/.config/mpv/mpv.conf`, so every
# curated value stays overridable per-user with no itera wiring in $HOME — and
# there is no system state to persist under impermanence, since mpv's own state
# (watch-later positions, `~/.config/mpv`) lives in the curated `.config` /
# `.local/state` home dirs the impermanence battery already persists.
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
      default = true;
      description = ''
        Decode video on the GPU where the driver supports it, by defaulting
        {option}`settings`.`hwdec` to `auto-safe` (mpv's own default is `no`,
        i.e. always software). On a host whose facter report shows an Intel GPU
        this also installs `intel-media-driver`, the VA-API driver nothing else
        in itera provides — AMD gets VA-API from mesa and NVIDIA from
        {option}`itera.nvidia`. Set to `false` for software decoding only; pin a
        specific method with `settings.hwdec` instead of turning this off.
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
        still override. itera sets only `hwdec` (see
        {option}`hardwareDecoding`); the file is not written at all when this ends
        up empty.
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
        true-colour text output everywhere else. `MPV_TERM_VO=<vo>` overrides the
        choice for a single run. Set to `false` to install the GUI player only.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages =
      lib.optional (cfg.package != null) cfg.package
      ++ lib.optional (cfg.terminal.enable && cfg.package != null) mpvTerm;

    # The one curated mpv option. `mkDefault` so `settings.hwdec = "vaapi"` (or
    # anything else) wins without having to turn the battery switch off.
    itera.desktop.videoPlayer.settings.hwdec = mkIf cfg.hardwareDecoding (mkDefault "auto-safe");

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
