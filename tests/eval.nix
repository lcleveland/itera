# Evaluation check for the disko + impermanence batteries.
#
# Full VM boot-tests of partitioning and a tmpfs root fight the NixOS test
# framework's own disk/root setup, so instead we evaluate a NixOS configuration
# with both features enabled and assert the generated config is what we expect.
# `nix build` on this derivation forces the evaluation and fails loudly if any
# assertion is false. Behavioural (boot-level) VM tests are a follow-up.
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

        itera.disko = {
          enable = true;
          device = "/dev/vda";
        };
        itera.impermanence.enable = true;
      }
    ];
  };
  cfg = eval.config;

  subvolumes = cfg.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  persistence = cfg.environment.persistence."/persist";

  # impermanence coerces string entries into attrsets ({ file = ...; } /
  # { directory = ...; }); tolerate either shape.
  fileNames = map (f: f.file or f) persistence.files;

  checks = {
    "disko provides a /nix subvolume" = subvolumes ? "/nix";
    "disko provides a /persist subvolume" = subvolumes ? "/persist";
    "root filesystem is tmpfs" = cfg.fileSystems."/".fsType == "tmpfs";
    "machine-id is persisted by default" = builtins.elem "/etc/machine-id" fileNames;
  };

  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
pkgs.runCommand "itera-disko-impermanence-eval" { } (
  if failed == [ ] then
    "touch $out"
  else
    throw "itera disko/impermanence eval check failed: ${lib.concatStringsSep "; " failed}"
)
