# itera — one command that namespaces itera's tooling as subcommands.
#
# itera's helper commands used to be a flat set of separate names
# (install-itera-testhost, itera-update, facter-report.sh). This groups them
# under a single `itera <group> <command>` entry point and gives new tooling a
# home. It is exposed two ways (see flake/cli.nix):
#
#   * as a flake package:   nix run github:lcleveland/itera#itera -- <args>
#   * baked onto the test hosts (dev/remote-access.nix), so an SSH session just
#     runs `itera <args>`.
#
# This is a thin router: each subcommand `exec`s the underlying tool, which is
# the canonical implementation and stays usable on its own. Those tools are put
# on PATH by the package's `runtimeInputs`, so they are called by bare name here.
# Flake-ref overrides still live in the delegated scripts (ITERA_INSTALL_FLAKE,
# ITERA_UPDATE_FLAKE).
#
# To add a subcommand: add a `case` arm below (and a `usage` line), then add its
# package to `runtimeInputs` in flake/cli.nix so the binary is on PATH.
#
# writeShellApplication supplies `set -euo pipefail` and runs shellcheck, so this
# file is plain bash with no preamble of its own.

usage() {
  cat <<'EOF'
itera — itera's tooling, under one command.

Usage: itera <command> [args...]

Commands:
  facter report [output-path]   Generate a nixos-facter report + a summary
                                mapping this machine to itera.* tuning options.
  testhost rebuild [nh args]    Rebuild this host in place from the latest remote
                                flake commit (nh os switch). Extra args pass to nh.
  testhost install [device]     Install itera-testhost onto a disk from a live
                                ISO (disko-install). Prompts for the disk if the
                                device is omitted.
  help                          Show this help.

Examples:
  itera facter report ./facter.json
  itera testhost rebuild --dry
  itera testhost install /dev/nvme0n1
EOF
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
  testhost)
    sub="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$sub" in
      rebuild) exec itera-update "$@" ;;
      install) exec install-itera-testhost "$@" ;;
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
