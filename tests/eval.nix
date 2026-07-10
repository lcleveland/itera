# Evaluation check for itera's system batteries (disko, impermanence, and the
# core-boot defaults: bootloader, nix, locale, networking).
#
# Full VM boot-tests of partitioning and a tmpfs root fight the NixOS test
# framework's own disk/root setup, so instead we evaluate a NixOS configuration
# with the features enabled and assert the generated config is what we expect.
# `nix build` on this derivation forces the evaluation and fails loudly if any
# assertion is false. The core-boot batteries additionally get a real EFI boot
# test in tests/nixos/core-boot.nix.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  eval = nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "25.05";

        # Turn on the opinionated core-boot batteries (bootloader, nix, locale,
        # networking) so this eval exercises them alongside disko/impermanence.
        itera = {
          enable = true;
          disko = {
            enable = true;
            device = "/dev/vda";
          };
          impermanence.enable = true;
        };
      }
    ];
  };
  cfg = eval.config;

  subvolumes = cfg.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  persistence = cfg.environment.persistence."/persist";

  # impermanence coerces string entries into attrsets ({ file = ...; } /
  # { directory = ...; }); tolerate either shape.
  fileNames = map (f: f.file or f) persistence.files;
  dirNames = map (d: d.directory or d) persistence.directories;

  checks = {
    # disko + impermanence
    "disko provides a /nix subvolume" = subvolumes ? "/nix";
    "disko provides a /persist subvolume" = subvolumes ? "/persist";
    "root filesystem is tmpfs" = cfg.fileSystems."/".fsType == "tmpfs";
    "machine-id is persisted by default" = builtins.elem "/etc/machine-id" fileNames;
    "NetworkManager connections are persisted" =
      builtins.elem "/etc/NetworkManager/system-connections" dirNames;
    "NetworkManager runtime state is persisted" = builtins.elem "/var/lib/NetworkManager" dirNames;
    "timesyncd clock state is persisted" = builtins.elem "/var/lib/systemd/timesync" dirNames;

    # core-boot batteries (activated by itera.enable)
    "systemd-boot is enabled" = cfg.boot.loader.systemd-boot.enable;
    "EFI variables are touchable" = cfg.boot.loader.efi.canTouchEfiVariables;
    "systemd initrd is enabled" = cfg.boot.initrd.systemd.enable;
    "flakes are enabled" = builtins.elem "flakes" cfg.nix.settings.experimental-features;
    "unfree is allowed" = cfg.nixpkgs.config.allowUnfree;
    "stateVersion is set" = cfg.system.stateVersion == "25.05";
    "time zone is set" = cfg.time.timeZone == "America/Chicago";
    "default locale is set" = cfg.i18n.defaultLocale == "en_US.UTF-8";
    "NetworkManager is enabled" = cfg.networking.networkmanager.enable;
    "hostname is set" = cfg.networking.hostName == "itera";

    # hardening (nix-mineral, auto-on with itera.enable)
    "nix-mineral hardening is enabled" = cfg.nix-mineral.enable;

    # binary-cache battery (auto-on with itera.enable)
    "nix-community substituter is configured" =
      builtins.elem "https://nix-community.cachix.org" cfg.nix.settings.extra-substituters;
  };

  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
pkgs.runCommand "itera-disko-impermanence-eval" { } (
  if failed == [ ] then
    "touch $out"
  else
    throw "itera system-battery eval check failed: ${lib.concatStringsSep "; " failed}"
)
