# itera's NVIDIA graphics battery: proprietary/open kernel modules, the container
# toolkit, PRIME hybrid graphics, and the Wayland workarounds NVIDIA needs.
#
# Ported from eiros' `system/hardware/graphics.nix`, but flipped to itera's
# posture: this is deliberately **opt-IN** (default OFF). NVIDIA drivers are
# machine-specific and unfree, so — like `itera.secureBoot` — they can't be
# safely defaulted on for a hardware-agnostic image. Enabling it is a single
# switch:
#
#   itera.nvidia.enable = true;
#
# which turns on `hardware.graphics`, selects the `nvidia` X/Wayland driver,
# loads the open kernel module, installs nvidia-settings, wires the container
# toolkit, and sets the Wayland env workarounds. Everything below `enable` is a
# further opt-out knob.
#
# The `nvidia` entry in `services.xserver.videoDrivers` is contributed ADDITIVELY
# (a plain list, not `mkDefault`), so it merges with — rather than being clobbered
# by — a hardware profile or a hand-written `services.xserver.videoDrivers` in the
# consumer's config. A `mkDefault` here would be silently dropped by any such
# normal-priority definition, leaving the container toolkit on with no active
# driver and tripping nixpkgs' driver assertion mid-`itera update`. The one
# consequence: to REMOVE the nvidia driver while keeping the battery on you must
# `lib.mkForce` `videoDrivers` — but enabling the battery means you want the
# driver, so that is the intended posture.
#
# PRIME (laptop hybrid graphics) is a nested opt-in: set `prime.enable = true`
# and supply the two PCI bus IDs (find them with `lspci`). Offload is the default
# mode; sync is the alternative — the two are mutually exclusive (asserted).
#
# Once on, the module gates its own `config` on `itera.enable && cfg.enable`, so
# it stays completely inert until you ask for it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption literalExpression;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) bool nullOr str;

  cfg = config.itera.nvidia;

  primeEnabled = cfg.enable && cfg.prime.enable;
  primeOffload = primeEnabled && cfg.prime.offload.enable;
  primeSync = primeEnabled && cfg.prime.sync.enable;
in
{
  options.itera.nvidia = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable NVIDIA GPU support: the kernel module, `hardware.graphics`, the
        `nvidia` video driver, and the Wayland workarounds. Opt-in (default off)
        because the drivers are unfree and hardware-specific. Requires
        {option}`itera.nix.allowUnfree` (on by default).
      '';
    };

    open = mkOption {
      type = bool;
      default = true;
      description = ''
        Use the NVIDIA open kernel module ({option}`hardware.nvidia.open`).
        Recommended for Turing (GTX 16xx / RTX 20xx) and newer. Set to `false`
        for the proprietary module on older GPUs.
      '';
    };

    settings = mkOption {
      type = bool;
      default = true;
      description = "Install the `nvidia-settings` GUI control panel.";
    };

    powerManagement = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable NVIDIA power management, which sets
        `NVreg_PreserveVideoMemoryAllocations=1` so the driver does not reclaim
        GPU memory across suspend/resume — this markedly improves Wayland
        rendering stability.
      '';
    };

    containerToolkit = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable the NVIDIA Container Toolkit so containers (podman/docker) can use
        the GPU. Composes with {option}`itera.virtualisation`.
      '';
    };

    enable32Bit = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable 32-bit graphics libraries ({option}`hardware.graphics.enable32Bit`),
        needed by 32-bit GL clients such as Steam/Wine.
      '';
    };

    prime = {
      enable = mkOption {
        type = bool;
        default = false;
        description = ''
          Enable NVIDIA PRIME for laptop hybrid (Intel iGPU + NVIDIA dGPU)
          graphics. Requires {option}`itera.nvidia.prime.intelBusId` and
          {option}`itera.nvidia.prime.nvidiaBusId`.
        '';
      };

      intelBusId = mkOption {
        type = nullOr str;
        default = null;
        example = "PCI:0:2:0";
        description = ''
          PCI bus ID of the Intel iGPU, in `PCI:X:Y:Z` form (from `lspci`).
          Required when {option}`itera.nvidia.prime.enable` is set.
        '';
      };

      nvidiaBusId = mkOption {
        type = nullOr str;
        default = null;
        example = "PCI:1:0:0";
        description = ''
          PCI bus ID of the NVIDIA dGPU, in `PCI:X:Y:Z` form (from `lspci`).
          Required when {option}`itera.nvidia.prime.enable` is set.
        '';
      };

      offload.enable = mkOption {
        type = bool;
        default = true;
        description = ''
          Use PRIME render offload (the recommended laptop default): the iGPU
          drives the display and the dGPU is used on demand via
          `nvidia-offload`. Mutually exclusive with
          {option}`itera.nvidia.prime.sync.enable`.
        '';
      };

      sync.enable = mkOption {
        type = bool;
        default = false;
        description = ''
          Use PRIME sync instead of offload (the dGPU renders everything, better
          for external displays wired to the dGPU). Mutually exclusive with
          {option}`itera.nvidia.prime.offload.enable`.
        '';
      };
    };

    wayland.wlrNoHardwareCursors = mkOption {
      type = bool;
      default = true;
      description = ''
        Set `WLR_NO_HARDWARE_CURSORS=1`, the wlroots workaround for an invisible
        or glitchy cursor on NVIDIA. Applies to itera's mango/wlroots desktop.
      '';
      example = literalExpression "false";
    };
  };

  config = mkMerge [
    # Keep a rebuild from HARD-FAILING on nixpkgs' nvidia-container-toolkit driver
    # assertion. That assertion (`services/hardware/nvidia-container-toolkit`) wants
    # `hardware.nvidia.datacenter.enable`, `"nvidia"` in
    # `services.xserver.videoDrivers`, or `suppressNvidiaDriverAssertion`. itera's
    # own stack sets the driver + videoDrivers together with the toolkit (below),
    # so it normally never trips itself — but the toolkit can end up on with no
    # active driver in states itera doesn't fully control:
    #   - a consumer's raw `hardware.nvidia-container-toolkit` /
    #     `virtualisation.docker/podman.enableNvidia`, or a fresh machine before
    #     facter detected the GPU — here `itera.nvidia` is OFF; or
    #   - `itera.nvidia` is ON, but a consumer / imported hardware profile
    #     `mkForce`s `services.xserver.videoDrivers` and drops `"nvidia"`.
    # In those states the build would abort with an opaque upstream error
    # mid-`itera update`. So whenever the toolkit is on but no driver is active,
    # suppress the assertion (overridable) and warn — the rebuild finishes; GPU
    # containers just won't work until the driver is on. The gate MIRRORS the
    # upstream assertion's failure condition and is intentionally NOT gated on
    # `cfg.enable` (the additive `videoDrivers` above satisfies the assertion the
    # real way in the common battery-on case, so this only fires in the edges).
    (mkIf
      (
        config.itera.enable
        && config.hardware.nvidia-container-toolkit.enable
        && !config.hardware.nvidia.datacenter.enable
        && !(builtins.elem "nvidia" config.services.xserver.videoDrivers)
      )
      {
        hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion = mkDefault true;

        warnings = [
          ''
            The NVIDIA container toolkit is enabled but no NVIDIA driver is active,
            so itera suppressed the upstream driver assertion to let this rebuild
            finish. GPU containers will NOT work until the driver is on:
              - if itera.nvidia is OFF: set itera.nvidia.enable = true (facter
                auto-enables it on an NVIDIA GPU — run `itera facter report` /
                `itera update` so the report exists), or set
                itera.nvidia.containerToolkit = false /
                virtualisation.docker.enableNvidia = false if you don't need GPU
                containers;
              - if itera.nvidia is ON: something in your configuration (an imported
                hardware profile, or an explicit services.xserver.videoDrivers) is
                overriding itera's "nvidia" entry — remove that definition or add
                "nvidia" to it (itera contributes it additively, so a plain
                videoDrivers list merges; only an mkForce drops it).
          ''
        ];
      }
    )

    (mkIf (config.itera.enable && cfg.enable) {
      assertions = [
        {
          assertion = config.nixpkgs.config.allowUnfree or false;
          message = ''
            itera.nvidia.enable requires unfree packages, but
            nixpkgs.config.allowUnfree is false. Set itera.nix.allowUnfree = true
            (its default) — the NVIDIA drivers are otherwise unavailable.
          '';
        }
        {
          assertion = !cfg.prime.enable || (cfg.prime.intelBusId != null && cfg.prime.nvidiaBusId != null);
          message = ''
            itera.nvidia.prime.enable is set; supply both
            itera.nvidia.prime.intelBusId and itera.nvidia.prime.nvidiaBusId
            (find them with `lspci`).
          '';
        }
        {
          assertion = !(primeOffload && primeSync);
          message = ''
            itera.nvidia.prime: offload and sync are mutually exclusive — enable
            only one of itera.nvidia.prime.offload.enable /
            itera.nvidia.prime.sync.enable.
          '';
        }
        {
          assertion =
            cfg.prime.intelBusId == null || lib.match "PCI:[0-9]+:[0-9]+:[0-9]+" cfg.prime.intelBusId != null;
          message = ''itera.nvidia.prime.intelBusId must be in "PCI:X:Y:Z" form (e.g. "PCI:0:2:0").'';
        }
        {
          assertion =
            cfg.prime.nvidiaBusId == null || lib.match "PCI:[0-9]+:[0-9]+:[0-9]+" cfg.prime.nvidiaBusId != null;
          message = ''itera.nvidia.prime.nvidiaBusId must be in "PCI:X:Y:Z" form (e.g. "PCI:1:0:0").'';
        }
      ];

      # GBM_BACKEND / __GLX_VENDOR_LIBRARY_NAME must NOT be set globally under PRIME
      # offload — they would force every client (including iGPU ones) through NVIDIA.
      # These use `environment.variables` (system-wide `/etc/set-environment`), not
      # `sessionVariables` like the other desktop modules, so the compositor/driver
      # see them from the very first process in the graphics stack rather than only
      # after PAM sets up the user session.
      environment.variables =
        (lib.optionalAttrs (!primeOffload) {
          GBM_BACKEND = "nvidia-drm";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          __GL_VRR_ALLOWED = "0";
        })
        // (lib.optionalAttrs cfg.wayland.wlrNoHardwareCursors {
          WLR_NO_HARDWARE_CURSORS = "1";
        });

      hardware = {
        graphics = {
          enable = mkDefault true;
          enable32Bit = mkDefault cfg.enable32Bit;
          extraPackages = mkDefault [
            pkgs.egl-wayland
            pkgs.nvidia-vaapi-driver
          ];
        };

        nvidia = {
          modesetting.enable = mkDefault true;
          powerManagement.enable = mkDefault cfg.powerManagement;
          nvidiaSettings = mkDefault cfg.settings;
          open = mkDefault cfg.open;

          prime = mkIf cfg.prime.enable {
            inherit (cfg.prime) intelBusId nvidiaBusId;
            offload = {
              enable = cfg.prime.offload.enable;
              enableOffloadCmd = cfg.prime.offload.enable;
            };
            sync.enable = cfg.prime.sync.enable;
          };
        };

        nvidia-container-toolkit.enable = mkIf cfg.containerToolkit (mkDefault true);
      };

      # Additive (plain list, NOT mkDefault) so it MERGES with any hardware-profile
      # or consumer `videoDrivers` instead of being clobbered by it — see the header.
      services.xserver.videoDrivers = [ "nvidia" ];
    })
  ];
}
