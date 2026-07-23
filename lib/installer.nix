# Builder for itera's FDE-aware installer, packaged for downstream flakes.
#
# A downstream config that consumes itera turns the whole install — partition,
# LUKS format, mount, `nixos-install`, and (for TPM2 hosts) passwordless
# auto-unlock enrollment — into a single command by wiring one package:
#
#   # in the downstream flake's perSystem
#   packages.installer = itera.lib.mkInstaller pkgs {
#     flake = "github:you/your-config";   # where `nix run <flake>#installer` lives
#   };
#
# then installing from a live ISO with:
#
#   sudo nix run github:you/your-config#installer            # pick host + disk from menus
#   sudo nix run github:you/your-config#installer -- myhost /dev/nvme0n1
#
# The host is chosen at runtime from the flake's `nixosConfigurations` (menu or
# argument), so one installer covers every host in the flake and there is no
# hand-written install script to maintain. All encryption behaviour is read from
# the evaluated host config, so enabling FDE downstream is just
# `itera.disko.encryption.enable = true` (+ `.tpm2.enable = true`) — see
# `modules/nixos/core/disko.nix`.
{ lib }:
{
  # mkInstaller pkgs { flake, diskName ? "main", host ? null, diskoInstall ? null, name ? "itera-install" }
  #
  #   pkgs         a nixpkgs instance (the downstream's `pkgs`).
  #   flake        default flake ref to install from, baked into the script as the
  #                ITERA_INSTALL_FLAKE default (still overridable via that env var).
  #   diskName     the disk key in `itera.disko` (the `--disk <name>` disko-install
  #                passes); "main" matches itera's layout.
  #   host         optional: preselect a host, skipping the host menu/argument.
  #   diskoInstall optional: a pinned `disko-install` package to put on PATH. When
  #                null (the default) the script fetches it with `nix run`, keeping
  #                the installer closure free of disko. Pass itera's own disko input
  #                to pin the installer to itera.disko's exact layout.
  #   name         the package + binary name (also `nix run`'s mainProgram).
  mkInstaller =
    pkgs:
    {
      flake,
      diskName ? "main",
      host ? null,
      diskoInstall ? null,
      name ? "itera-install",
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.util-linux
        # systemd-cryptenroll + udevadm, for the post-install TPM2 enrollment the
        # installer runs when the target host sets encryption.tpm2.enable.
        pkgs.systemd
      ]
      ++ lib.optional (diskoInstall != null) diskoInstall;
      # Bake the flake/disk defaults into the environment the shared script reads,
      # each still overridable at run time. `??=`-style `${VAR:-default}` keeps an
      # explicit override winning over the baked default.
      text = ''
        export ITERA_INSTALL_FLAKE="''${ITERA_INSTALL_FLAKE:-${flake}}"
        export ITERA_DISK_NAME="''${ITERA_DISK_NAME:-${diskName}}"
      ''
      + lib.optionalString (host != null) ''
        export ITERA_HOST="''${ITERA_HOST:-${host}}"
      ''
      + builtins.readFile ../cli/install.sh;
    };
}
