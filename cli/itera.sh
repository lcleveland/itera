# itera — one command to control your itera system.
#
# Shipped to every consumer by the `itera.cli` battery (modules/nixos/core/cli.nix)
# and packaged for `nix run` (flake/cli.nix). The consumer build carries the
# system-management verbs (facter/rebuild/update/gc); the full build used from the
# itera repo and on the dev test hosts additionally carries the `testhost` verbs.
#
# This is a thin router: each subcommand `exec`s the underlying tool. The tools
# are on PATH via the package's `runtimeInputs`, so they are called by bare name
# — and the `testhost` group is present only when its (itera-repo dev) tools are,
# which is how the consumer build stays free of them.
#
# To add a subcommand: add a `case` arm and a `usage` line, add its package to the
# right `runtimeInputs` in flake/cli.nix, and add an entry to the carapace specs
# in cli/ (itera.carapace.yaml for the full command, itera-consumer.carapace.yaml
# for the shipped one).
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own.

# Regenerate the nixos-facter hardware report before a build, when the facter
# battery has auto-generation on. modules/nixos/core/facter.nix drops the
# effective settings at /etc/itera/facter.env; an absent/AUTOGEN=0 file means the
# feature is off, so we behave exactly like a plain `nh` call (return non-zero and
# the caller skips both the regen and `--impure`). Returns 0 only when it wrote a
# report and the build should therefore be impure.
itera_facter_refresh() {
  [ -r /etc/itera/facter.env ] || return 1
  # shellcheck disable=SC1091
  . /etc/itera/facter.env
  [ "${ITERA_FACTER_AUTOGEN:-0}" = "1" ] || return 1
  local path="${ITERA_FACTER_REPORT_PATH:-/var/lib/itera/facter.json}"
  echo "itera: refreshing nixos-facter report at ${path} …"
  sudo mkdir -p "$(dirname "$path")"
  # sudo resets PATH (secure_path), so resolve the store path before elevating.
  sudo -- "$(command -v nixos-facter)" -o "$path"
  # nixos-facter writes the report root-only; make it world-readable so a
  # non-root `nixos-rebuild build --impure` can read it too (the hardware
  # inventory is not secret). The `nh`-driven rebuild below already runs the
  # eval as root, so this is belt-and-suspenders.
  sudo chmod 0644 "$path"
}

# Read this host's configured update source. The update battery
# (modules/nixos/core/update.nix) drops the effective settings at
# /etc/itera/update.env: which flake to build (ITERA_UPDATE_FLAKE), which
# nixosConfiguration attribute this host is (ITERA_UPDATE_CONFIGURATION), and
# whether the flake is a remote ref (ITERA_UPDATE_REMOTE=1) or a local path (0).
# Populates SRC_ARGS with the resulting `nh` arguments (flake installable +
# `--hostname`). An absent file means no configured source, so the verbs behave
# exactly like a plain `nh` call.
SRC_ARGS=()
itera_update_source() {
  SRC_ARGS=()
  ITERA_UPDATE_REMOTE=""
  [ -r /etc/itera/update.env ] || return 0
  # shellcheck disable=SC1091
  . /etc/itera/update.env
  [ -n "${ITERA_UPDATE_FLAKE:-}" ] && SRC_ARGS+=("$ITERA_UPDATE_FLAKE")
  [ -n "${ITERA_UPDATE_CONFIGURATION:-}" ] && SRC_ARGS+=(--hostname "$ITERA_UPDATE_CONFIGURATION")
  return 0
}

# The fetch flag for the `update`/`update-boot` verbs: refresh a remote flake ref
# to its newest revision, or bump a local checkout's flake.lock. Call after
# itera_update_source so ITERA_UPDATE_REMOTE is set.
itera_update_fetch_flag() {
  if [ "${ITERA_UPDATE_REMOTE:-0}" = "1" ]; then echo "--refresh"; else echo "--update"; fi
}

# testhost tooling is itera-repo dev-only. It is absent from the consumer build,
# so guide the user to the flake instead of failing obscurely.
require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "itera: '$1' is not available here — 'itera testhost' is itera-repo dev tooling." >&2
    echo "       Run it from the flake instead:" >&2
    echo "         nix run github:lcleveland/itera#itera -- testhost ..." >&2
    exit 1
  }
}

usage() {
  cat <<'EOF'
itera — control your itera system.

Usage: itera <command> [args...]

Commands:
  facter report [output-path]  Generate a nixos-facter hardware report + a summary
                               mapping this machine to itera.* tuning options.
  rebuild [nh args]            Rebuild this system from your configured flake
                               (nh os switch; uses itera.update.flake and
                               itera.update.configuration).
  update [nh args]             Fetch the newest config, then rebuild (nh os
                               switch; --refresh for a remote itera.update.flake,
                               --update for a local one).
  boot [nh args]               Rebuild from your flake, but apply on next reboot
                               instead of now (nh os boot).
  update-boot [nh args]        Update your flake inputs, then apply on next reboot
                               (nh os boot --update).
  gc [nh args]                 Prune old generations to free space (nh clean all).
  firmware status              Show devices and their current firmware (fwupdmgr
                               get-devices).
  firmware refresh             Refresh firmware metadata from the LVFS (fwupdmgr
                               refresh).
  firmware update              Install available firmware updates (fwupdmgr
                               update).
  help                         Show this help.
EOF
  # Only advertise the dev verbs on a build that actually has them.
  if command -v itera-update >/dev/null 2>&1 || command -v install-itera-testhost >/dev/null 2>&1; then
    cat <<'EOF'

Dev commands (itera repo / test hosts):
  testhost rebuild [nh args]   Rebuild itera's test host in place from itera's flake.
  testhost install [device]    Install itera-testhost onto a disk (disko-install).
EOF
  fi
}

# `${1:-}` so an unset arg does not trip `set -u`.
cmd="${1:-help}"
[ "$#" -gt 0 ] && shift

case "$cmd" in
  facter)
    sub="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$sub" in
      report) exec facter-report "$@" ;;
      *)
        echo "itera facter: unknown subcommand '${sub:-}' (expected: report)" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    ;;
  rebuild)
    itera_update_source
    if itera_facter_refresh; then
      exec nh os switch "${SRC_ARGS[@]}" "$@" -- --impure
    else
      exec nh os switch "${SRC_ARGS[@]}" "$@"
    fi
    ;;
  update)
    itera_update_source
    fetch="$(itera_update_fetch_flag)"
    if itera_facter_refresh; then
      exec nh os switch "${SRC_ARGS[@]}" "$fetch" "$@" -- --impure
    else
      exec nh os switch "${SRC_ARGS[@]}" "$fetch" "$@"
    fi
    ;;
  boot)
    itera_update_source
    if itera_facter_refresh; then
      exec nh os boot "${SRC_ARGS[@]}" "$@" -- --impure
    else
      exec nh os boot "${SRC_ARGS[@]}" "$@"
    fi
    ;;
  update-boot)
    itera_update_source
    fetch="$(itera_update_fetch_flag)"
    if itera_facter_refresh; then
      exec nh os boot "${SRC_ARGS[@]}" "$fetch" "$@" -- --impure
    else
      exec nh os boot "${SRC_ARGS[@]}" "$fetch" "$@"
    fi
    ;;
  gc) exec nh clean all "$@" ;;
  firmware)
    sub="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$sub" in
      status) exec fwupdmgr get-devices "$@" ;;
      refresh) exec fwupdmgr refresh "$@" ;;
      update) exec fwupdmgr update "$@" ;;
      *)
        echo "itera firmware: unknown subcommand '${sub:-}' (expected: status, refresh, update)" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    ;;
  testhost)
    sub="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$sub" in
      rebuild)
        require itera-update
        exec itera-update "$@"
        ;;
      install)
        require install-itera-testhost
        exec install-itera-testhost "$@"
        ;;
      *)
        echo "itera testhost: unknown subcommand '${sub:-}' (expected: rebuild, install)" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    ;;
  help | --help | -h)
    usage
    ;;
  *)
    echo "itera: unknown command '${cmd}'" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
