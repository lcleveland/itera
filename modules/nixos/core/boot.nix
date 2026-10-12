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
  options,
  lib,
  pkgs,
  iteraLib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault mkAfter;
  inherit (lib.types)
    bool
    int
    str
    nullOr
    attrs
    ;

  cfg = config.itera.boot;
  mineralQuiet =
    (config.nix-mineral.enable or false) && (config.nix-mineral.settings.debug.quiet-boot or false);
in
{
  # The systemd initrd is NixOS's own default since 26.05; set
  # `boot.initrd.systemd.enable` directly.
  imports = [
    (lib.mkRenamedOptionModule
      [ "itera" "boot" "initrd" "systemd" "enable" ]
      [ "boot" "initrd" "systemd" "enable" ]
    )
  ];

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

        timeout = mkOption {
          type = nullOr int;
          default = 1;
          example = 0;
          description = ''
            Seconds the systemd-boot menu waits before booting the default entry.
            `0` boots immediately (hold a key during POST to force the menu);
            `null` restores upstream's behaviour of waiting indefinitely. The
            default (`1`) keeps the menu briefly reachable without adding the ~5s
            the unconfigured menu otherwise costs on every boot.
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
      example = lib.literalExpression "pkgs.linuxPackages";
      description = ''
        Kernel package set to boot (e.g. {command}`pkgs.linuxPackages` for the
        NixOS default LTS kernel). {command}`null` (the default) selects the
        latest mainline kernel ({command}`pkgs.linuxPackages_latest`).
      '';
    };

    plymouth.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Show the itera Plymouth theme at boot (the Flow mark on the system look's
        `surface`, in its starting mode, with prompts in Roboto Flex) and boot
        silently: `quiet`, `udev.log_level=3` and `rd.systemd.show_status=auto`
        (the kernel log level stays the hardening layer's
        {option}`boot.consoleLogLevel`, 0). Per-user look overrides don't reach it,
        and token changes show after a rebuild and reboot.
      '';
    };

    trustBootloaderEntropy = mkOption {
      type = bool;
      default = true;
      description = ''
        Credit the bootloader-supplied random seed to initialise the kernel CRNG
        (`random.trust_bootloader=on`), overriding the hardening layer
        (nix-mineral), which turns every fast entropy source off.

        With all fast sources disabled — CPU RDRAND (`random.trust_cpu=off`),
        the bootloader seed, and the TPM hwrng — the CRNG cannot seed until
        enough interrupt jitter accumulates, which on this hardware takes ~70s.
        `getrandom()` in the initrd blocks the entire time, stalling switch-root
        and adding over a minute to boot. Crediting the systemd-boot random seed
        (`/loader/random-seed` on the ESP + the `LoaderRandomSeed` EFI variable,
        both maintained automatically) restores instant CRNG init without
        trusting the CPU vendor's RNG — nix-mineral's specific objection to
        `trust_cpu`. Set to false to keep the seed uncredited and accept the slow
        boot (maximum-paranoia hosts only).
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
        }
        # Automatic boot assessment: a generation that never reaches
        # boot-complete.target is skipped for the previous one, so a bad
        # unattended update rolls itself back. nixpkgs 26.11+ only.
        // lib.optionalAttrs (options.boot.loader.systemd-boot ? bootCounting) {
          bootCounting.enable = mkDefault true;
        };
        efi.canTouchEfiVariables = mkDefault cfg.loader.efi.canTouchEfiVariables;
        timeout = mkDefault cfg.loader.systemd-boot.timeout;
      };

      kernelParams = lib.mkMerge [
        # Override nix-mineral's `random.trust_bootloader=off`. kernel bool params
        # take their last occurrence, so appending with mkAfter wins. See the
        # option description for the boot-time entropy stall this fixes.
        (mkIf cfg.trustBootloaderEntropy (mkAfter [ "random.trust_bootloader=on" ]))
        # Silent boot behind the splash. A mkDefault list would be dropped by any
        # other kernelParams definition, so these follow the opt-out instead.
        # The kernel log level is nix-mineral's (`boot.consoleLogLevel = 0`,
        # quieter than 3), so it is left alone. Its quiet-boot already adds
        # `quiet` and `udev.log_level=3`, so they're only added without it.
        (mkIf cfg.plymouth.enable (
          lib.optionals (!mineralQuiet) [
            "quiet"
            "udev.log_level=3"
          ]
          ++ [ "rd.systemd.show_status=auto" ]
        ))
      ];

      # The system look's starting mode (auto starts dark).
      plymouth = mkIf cfg.plymouth.enable {
        enable = mkDefault true;
        theme = mkDefault "itera";
        themePackages = [
          (iteraLib.brand.plymouthTheme pkgs (iteraLib.look.resolve config null).startColors)
        ];
        font = mkDefault "${pkgs.roboto-flex}/share/fonts/truetype/RobotoFlex[GRAD,XOPQ,XTRA,YOPQ,YTAS,YTDE,YTFI,YTLC,YTUC,opsz,slnt,wdth,wght].ttf";
      };

      tmp = {
        useTmpfs = mkDefault cfg.tmp.useTmpfs;
        tmpfsSize = mkDefault cfg.tmp.size;
      };

      kernelPackages = mkDefault (
        if cfg.kernelPackages != null then cfg.kernelPackages else pkgs.linuxPackages_latest
      );
    };
  };
}
