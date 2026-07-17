#!/usr/bin/env bash
# Generate a hardware tuning report for an itera host.
#
# itera describes a host entirely through `itera.*` options — there is no
# generated `hardware-configuration.nix`. A handful of knobs are inherently
# per-machine and have no sensible default: the CPU vendor, the install disk,
# the NVIDIA PRIME PCI bus IDs, and the opt-in nixos-facter report. This script
# collapses "figure those out" into one command. It:
#
#   1. captures a machine-readable `facter.json` with the `nixos-facter` CLI, and
#   2. prints a summary that maps THIS machine's hardware straight to the
#      `itera.*` options you set in your flake.
#
# Run it on the target machine (a NixOS live ISO is fine) as root — nixos-facter
# refuses to probe the hardware otherwise:
#
#     sudo bash facter-report.sh [output-path]
#
# It is also the `itera facter report` subcommand and the `facter-report` flake
# package (see flake/cli.nix), e.g.  sudo nix run github:lcleveland/itera#itera -- facter report
#
# Or straight from GitHub, no clone needed (the live ISO ships nix-command/flakes
# disabled, so this enables them for the facter run):
#
#     curl -fsSL https://raw.githubusercontent.com/lcleveland/itera/main/facter-report.sh | sudo bash
#
# The report path defaults to `./facter.json`; pass a path to override it. Once
# written, commit `facter.json` into your flake (flakes ignore untracked files)
# and point itera at it:  itera.hardware.facter.reportPath = ./facter.json;
set -euo pipefail

OUTPUT="${1:-./facter.json}"

# Section header helper — keeps the summary visually scannable.
h() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — nixos-facter refuses to probe hardware otherwise:" >&2
  echo "  sudo bash facter-report.sh ${OUTPUT}" >&2
  exit 1
fi

# 1. Capture the facter report. Route through nixpkgs so nothing needs
#    installing, and enable the experimental features a live ISO ships disabled.
echo "Generating facter report at ${OUTPUT} …"
nix --extra-experimental-features 'nix-command flakes' \
  run nixpkgs#nixos-facter -- -o "$OUTPUT"

# 2. Tuning summary, derived from the live-system tools that feed the same data
#    facter uses. Each probe is guarded so a missing tool downgrades that one
#    section to a note instead of aborting the whole report.
printf '\n\033[1m=== itera hardware tuning report ===\033[0m\n'
note "facter.json written to ${OUTPUT}"

# --- CPU vendor -> itera.hardware.cpu ---------------------------------------
h "CPU"
if command -v lscpu >/dev/null 2>&1; then
  vendor="$(lscpu | awk -F: '/^Vendor ID/ { gsub(/^[ \t]+/, "", $2); print $2; exit }')"
  case "$vendor" in
    GenuineIntel) note 'itera.hardware.cpu = "intel";' ;;
    AuthenticAMD) note 'itera.hardware.cpu = "amd";' ;;
    *) note "unrecognised vendor \"${vendor:-unknown}\" — leave itera.hardware.cpu = \"auto\";" ;;
  esac
  note "(\"auto\", the default, is always safe — it just also loads the other vendor's microcode.)"
else
  note "lscpu not found (nixpkgs#util-linux) — leave itera.hardware.cpu = \"auto\";"
fi

# --- GPUs -> itera.nvidia / PRIME -------------------------------------------
h "Graphics"
if command -v lspci >/dev/null 2>&1; then
  # Convert lspci's hex "BB:DD.F" slot to the decimal "PCI:B:D:F" the option wants.
  busid() {
    local slot="$1" b d f
    b="${slot%%:*}"          # BB
    slot="${slot#*:}"        # DD.F
    d="${slot%%.*}"          # DD
    f="${slot##*.}"          # F
    printf 'PCI:%d:%d:%d' "0x${b}" "0x${d}" "0x${f}"
  }

  # Display controllers = PCI class 03xx (VGA/3D/display). Filter on the class
  # code lspci prints in brackets rather than "-d ::0300", since older lspci only
  # honours the last "-d". "-D" prints the domain, which PRIME's domain-less
  # PCI:B:D:F form drops below.
  mapfile -t gpus < <(lspci -Dnn 2>/dev/null | grep -E ' \[03[0-9a-f]{2}\]:')

  if [ "${#gpus[@]}" -eq 0 ]; then
    note "no display controller reported by lspci."
  else
    nvidia_slot="" igpu_slot=""
    for line in "${gpus[@]}"; do
      slot="${line%% *}"       # 0000:01:00.0
      slot="${slot#*:}"        # 01:00.0  (drop domain)
      note "$line"
      case "$line" in
        *"[10de:"*) nvidia_slot="$slot" ;;                 # NVIDIA vendor id
        *"[8086:"* | *"[1002:"*) [ -z "$igpu_slot" ] && igpu_slot="$slot" ;;  # Intel / AMD
      esac
    done

    if [ -n "$nvidia_slot" ]; then
      printf '\n'
      note "itera.nvidia.enable = true;"
      if [ -n "$igpu_slot" ]; then
        note "# hybrid graphics detected — PRIME (offload is the default mode):"
        note "itera.nvidia.prime.enable = true;"
        note "itera.nvidia.prime.intelBusId  = \"$(busid "$igpu_slot")\";"
        note "itera.nvidia.prime.nvidiaBusId = \"$(busid "$nvidia_slot")\";"
        note "# NOTE: intelBusId holds the integrated GPU's id even on AMD iGPUs."
      fi
      note "# Set itera.nvidia.open = false for pre-Turing (older than GTX 16xx) GPUs."
    else
      note "no NVIDIA GPU — leave itera.nvidia.enable at its default (false)."
    fi
  fi
else
  note "lspci not found (nixpkgs#pciutils) — skipping GPU detection."
fi

# --- Disks -> itera.disko.device --------------------------------------------
h "Disks"
if command -v lsblk >/dev/null 2>&1; then
  note "Candidate install devices (itera.disko.device):"
  # Real disks only: TYPE=="disk", excluding virtual block devices (zram — which
  # itera's zramSwap always creates — plus loop/ram/optical). Drop the TYPE
  # column and let `read` fold the space-containing model into the last field.
  while read -r name size model; do
    note "  /dev/${name}  ${size}  ${model:-}"
  done < <(lsblk -dno NAME,SIZE,MODEL,TYPE |
    awk '$NF == "disk" && $1 !~ /^(zram|loop|sr|ram|fd)/ { $NF = ""; sub(/[ \t]+$/, ""); print }')
  note "e.g. itera.disko.device = \"/dev/nvme0n1\";"
  note "WARNING: itera.disko WIPES the chosen device on install."
else
  note "lsblk not found (nixpkgs#util-linux) — inspect disks manually for itera.disko.device."
fi

# --- Firmware ----------------------------------------------------------------
h "Firmware"
note "itera.hardware.redistributableFirmware (default true) covers Wi-Fi/GPU"
note "firmware blobs — no action needed unless you deliberately disabled it."

# 3. Point at the report.
h "Next steps"
note "This is an inspection/one-off report. itera normally regenerates the report"
note "automatically on every rebuild (itera.hardware.facter.autoGenerate, default"
note "on) at /var/lib/itera/facter.json — nothing to commit. To manage it yourself"
note "instead, set autoGenerate = false and commit + point at this file:"
note "  itera.hardware.facter.reportPath = ./facter.json;"
note "facter derives kernel modules/microcode/drivers from it (and itera auto-enables"
note "itera.nvidia when it sees an NVIDIA GPU); the summary above covers the knobs"
note "facter does not (disk, CPU enum, NVIDIA PRIME bus IDs)."
printf '\n'
