# mpv-term — play video inside the terminal, with real pixels when the terminal
# can show them.
#
# Shipped by itera's video-player battery (modules/nixos/desktop/video-player.nix)
# next to the GUI player. mpv can render into a terminal, but *which* way is right
# is a property of the terminal you happen to be sitting in:
#
#   * --vo=kitty  the kitty graphics protocol — actual pixels, actual video.
#                 itera's terminal battery ships WezTerm, which implements the
#                 protocol (`enable_kitty_graphics`, pinned on by
#                 modules/programs/wezterm.nix); kitty and Ghostty speak it too.
#   * --vo=tct    true-colour text — half-block characters. Coarse, but it needs
#                 nothing beyond 24-bit colour, so it is the fallback everywhere
#                 else and the reason this command always plays *something*.
#   * --vo=sixel  deliberately NOT offered: nixpkgs builds mpv with
#                 `sixelSupport = false`, so this binary has no sixel output at
#                 all (`mpv --vo=help` lists none). Reaching it would mean
#                 rebuilding mpv from source for every consumer.
#
# Detection is two-stage: an environment allow-list for the terminals that name
# themselves (no round-trip, and it works even when stdin is not a tty), then the
# protocol's own capability query for everything else. `MPV_TERM_VO=<vo>` skips
# both, and an explicit `--vo` in the arguments is always left alone.
#
# Picking `kitty` is only half of it. A still image is one transfer; a video is a
# new image EVERY FRAME, and the protocol's default medium is base64 escape codes
# down the pty. Measured on a 1280x720 clip in a 1600x800 window, that is ~137 MB
# of escape codes for two seconds of video — ~67 MB/s. mpv sustains it; the
# terminal on the other end does not, which is what "it stops on the first frame"
# actually is. `--vo-kitty-use-shm` hands over a shared-memory object instead and
# takes the wire traffic to ~0, so it is on wherever it can be trusted (see the
# gate below). The options this adds are PREPENDED, so anything the caller passes
# still wins.
#
# Over SSH there is no shared memory to hand over and the escape-code path is all
# there is. It is genuinely slow at a large window size — `MPV_TERM_VO=tct`, or
# `--vo-kitty-width`/`--vo-kitty-height` to cap the image, are the ways out.
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own. mpv and stty (coreutils) come
# from the wrapper's runtimeInputs.

# Restoring the tty from the capability query below. Global rather than a local,
# because the EXIT trap that guarantees the restore outlives the function.
mpv_term_stty_saved=""

# A terminal multiplexer sits between us and the terminal that actually draws.
# tmux and screen do not forward the graphics protocol's APC sequences (tmux only
# with `allow-passthrough`, and even then the query's reply is not routed back),
# so a kitty-capable outer terminal is not reachable from in here — TERM_PROGRAM
# and friends still leak through and would otherwise say it is.
in_multiplexer() {
  if [ -n "${TMUX:-}" ] || [ -n "${STY:-}" ]; then
    return 0
  fi
  case "${TERM:-}" in
    screen | screen.* | tmux | tmux-*) return 0 ;;
  esac
  return 1
}

# Terminals that implement the kitty graphics protocol and announce themselves in
# the environment. Checked first so the common case costs no round-trip.
#
# Naming the terminal (rather than just answering yes/no) is what unlocks shared
# memory transfer below: all three of these are known to implement it, whereas a
# terminal that merely answers the capability query might not, and asking for it
# there would draw nothing at all.
kitty_terminal=""
kitty_graphics_by_env() {
  case "${TERM:-}" in
    xterm-kitty)
      kitty_terminal=kitty
      return 0
      ;;
    xterm-ghostty)
      kitty_terminal=ghostty
      return 0
      ;;
  esac
  case "${TERM_PROGRAM:-}" in
    WezTerm)
      kitty_terminal=wezterm
      return 0
      ;;
    ghostty)
      kitty_terminal=ghostty
      return 0
      ;;
  esac
  if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    kitty_terminal=kitty
    return 0
  fi
  if [ -n "${GHOSTTY_RESOURCES_DIR:-}" ]; then
    kitty_terminal=ghostty
    return 0
  fi
  return 1
}

# Ask the terminal itself, for everything the allow-list does not name. This is
# the protocol's documented capability probe: a 1x1 image sent with `a=q` (query
# only — nothing is drawn), followed by a Primary Device Attributes request. A
# terminal that speaks the protocol answers `_Gi=31;OK`; one that does not
# answers only DA1, and that reply's terminating `c` is what bounds the read
# instead of the timeout.
kitty_graphics_by_query() {
  # No tty means no reply — and nothing worth drawing into either.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    return 1
  fi

  mpv_term_stty_saved=$(stty -g 2>/dev/null) || return 1
  # A ^C mid-probe must not leave the terminal in raw mode with echo off.
  trap 'if [ -n "$mpv_term_stty_saved" ]; then stty "$mpv_term_stty_saved" 2>/dev/null || true; fi' \
    EXIT INT TERM
  # Raw: the answer has to arrive as bytes rather than as a line the tty holds
  # until Enter, and it must not be echoed into the middle of the display.
  stty raw -echo 2>/dev/null || return 1

  local response=""
  printf '\033_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\033\\\033[c'
  IFS= read -r -d c -t 2 response || true

  stty "$mpv_term_stty_saved" 2>/dev/null || true
  trap - EXIT INT TERM
  mpv_term_stty_saved=""

  case "$response" in
    *_Gi=31\;OK*) return 0 ;;
  esac
  return 1
}

# An explicit --vo means the caller has already chosen; everything after `--` is
# a file name, not an option, so the scan stops there.
explicit_vo=0
for arg in "$@"; do
  case "$arg" in
    --) break ;;
    --vo | --vo=* | -vo | -vo=*)
      explicit_vo=1
      break
      ;;
  esac
done

if [ "$explicit_vo" -eq 0 ]; then
  vo="${MPV_TERM_VO:-}"

  if [ -z "$vo" ]; then
    if in_multiplexer; then
      vo=tct
    elif kitty_graphics_by_env || kitty_graphics_by_query; then
      vo=kitty
    else
      vo=tct
    fi
  fi

  # Half-blocks are emitted as 24-bit colour by default. A terminal that only
  # does 256 colours renders that as garbage, so ask for the 256-colour path
  # unless COLORTERM claims otherwise.
  if [ "$vo" = tct ]; then
    case "${COLORTERM:-}" in
      truecolor | 24bit) ;;
      *) set -- --vo-tct-256=yes "$@" ;;
    esac
  fi

  if [ "$vo" = kitty ]; then
    # WITHOUT this, in-terminal video does not work — it stops on the first
    # frame. The protocol's default transmission medium is base64 escape codes
    # through the pty, and a video is not one image but a new one every frame:
    # measured on a 1280x720 clip in a 1600x800 window, mpv emits ~67 MB/s of
    # escape codes. mpv keeps up; no terminal emulator does. Shared memory hands
    # over a memfd instead and drops that to ~0 bytes on the wire.
    #
    # Gated on the terminal being one we NAMED above, not merely one that
    # answered the capability query: shm is an optional part of the protocol
    # (WezTerm implements it — wezterm#1810), and a terminal without it would
    # display nothing rather than fall back. Gated on a local session too — a
    # memfd means nothing to a terminal on the other end of an SSH connection,
    # which is exactly when the slow-but-portable escape codes are the only
    # option.
    if [ -n "$kitty_terminal" ] && [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ]; then
      set -- --vo-kitty-use-shm=yes "$@"
    fi

    # mpv repaints its terminal status line under every frame, which WezTerm
    # renders as a status message flashing at the top for the whole video
    # (wezterm#4112, still open). The OSD is unaffected — this drops only the
    # one-line status readout that the image is covering anyway.
    set -- --term-status-msg= "$@"
  fi

  # Both terminal outputs scale every frame to the terminal's grid on the CPU,
  # and mpv's default scaler is built for a real display, not for an image this
  # small. mpv's own manual points at this profile for the terminal VOs.
  set -- --profile=sw-fast "$@"

  set -- "--vo=$vo" "$@"
fi

exec mpv "$@"
