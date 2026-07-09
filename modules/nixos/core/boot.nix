# itera's boot battery: bootloader, early-boot (initrd), and /tmp.
#
# This is the piece that turns itera's disk layout (`itera.disko`) into a system
# that actually boots: it installs systemd-boot on the ESP and selects the modern
# systemd-based initrd. Together with `itera.hardware` (which provides the initrd
# kernel modules that mount the root device) this is enough to reach a login
# prompt — no consumer-supplied `hardware-configuration.nix` required.
#
# Like the other opinionated defaults, config is gated on the master `itera.enable`
# and every value uses `mkDefault`, so the whole battery is opt-out and each knob
# is individually overridable. (Contrast with `itera.disko`/`itera.impermanence`,
# which gate on their own `enable` because they are destructive/foundational.)
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    bool
    int
    str
    nullOr
    attrs
    ;

  cfg = config.itera.boot;
in
{
  options.itera.boot = {
    loader = {
      systemd-boot = {
        enable = mkOption {
          type = bool;
          default = true;
          description = "Install systemd-boot on the EFI System Partition.";
        };

        configurationLimit = mkOption {
          type = int;
          default = 10;
          description = ''
            Maximum number of generations to keep as systemd-boot entries on the ESP.
          '';
        };
      };

      efi.canTouchEfiVariables = mkOption {
        type = bool;
        default = true;
        description = ''
          Allow the installer to modify EFI boot variables (needed for systemd-boot
          to register itself as a boot entry on most machines).
        '';
      };
    };

    initrd.systemd.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Use the modern systemd-based initrd instead of the legacy shell-script one.
        Cleaner device/mount handling and the recommended path for LUKS setups.
      '';
    };

    tmp = {
      useTmpfs = mkOption {
        type = bool;
        default = true;
        description = ''
          Mount {file}`/tmp` as a RAM-backed tmpfs. Faster for build artifacts and
          avoids unnecessary disk write wear.
        '';
      };

      size = mkOption {
        type = str;
        default = "50%";
        description = ''
          Maximum size of the tmpfs {file}`/tmp`, as a percentage of RAM or a fixed
          size (e.g. {command}`"8G"`).
        '';
      };
    };

    kernelPackages = mkOption {
      type = nullOr attrs;
      default = null;
      example = lib.literalExpression "pkgs.linuxPackages_latest";
      description = ''
        Kernel package set to boot (e.g. {command}`pkgs.linuxPackages_latest`).
        {command}`null` (the default) keeps the NixOS default kernel.
      '';
    };
  };

  config = mkIf config.itera.enable {
    assertions = [
      {
        assertion = !cfg.loader.systemd-boot.enable || cfg.loader.efi.canTouchEfiVariables;
        message = "itera.boot: systemd-boot requires EFI — do not set itera.boot.loader.efi.canTouchEfiVariables = false while systemd-boot is enabled, unless you register the boot entry manually.";
      }
    ];

    boot = {
      loader = {
        systemd-boot = {
          enable = mkDefault cfg.loader.systemd-boot.enable;
          configurationLimit = mkDefault cfg.loader.systemd-boot.configurationLimit;
        };
        efi.canTouchEfiVariables = mkDefault cfg.loader.efi.canTouchEfiVariables;
      };

      initrd.systemd.enable = mkDefault cfg.initrd.systemd.enable;

      tmp = {
        useTmpfs = mkDefault cfg.tmp.useTmpfs;
        tmpfsSize = mkDefault cfg.tmp.size;
      };

      kernelPackages = mkIf (cfg.kernelPackages != null) (mkDefault cfg.kernelPackages);
    };
  };
}
