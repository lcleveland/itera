# itera's system-hardening battery.
#
# A thin, opinionated wrapper over nix-mineral (bundled by
# `modules/nixos/default.nix`), which layers Kicksecure/security-misc-style
# hardening onto the system: kernel + network sysctls, kernel command-line
# lockdown, restricted ptrace, and more.
#
# Follows the opt-out shape of the core-boot batteries (see `networking.nix`):
# gated on the master `itera.enable` with `mkDefault` values, so hardening comes
# along automatically but every knob is overridable. A per-feature
# `itera.hardening.enable` (default true) lets a consumer switch the whole layer
# off without giving up the rest of itera.
#
# Only the two knobs most people touch — the master toggle and the preset — are
# surfaced here. Granular tuning is done directly against the underlying
# `nix-mineral.settings.*` / `nix-mineral.extras.*` options, which stay reachable
# because the upstream module is bundled (exactly how `itera.disko` leaves the
# native `disko.*` options in place).
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
    enum
    either
    listOf
    ;

  cfg = config.itera.hardening;

  presetEnum = enum [
    "default"
    "compatibility"
    "performance"
    "maximum"
  ];
in
{
  options.itera.hardening = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Apply the nix-mineral hardening layer. On by default whenever
        {option}`itera.enable` is set; set this to `false` to opt out of
        hardening while keeping the rest of itera.
      '';
    };

    preset = mkOption {
      type = either presetEnum (listOf presetEnum);
      default = "default";
      example = [
        "compatibility"
        "performance"
      ];
      description = ''
        nix-mineral preset (or ordered list of presets, all layered on top of
        `default`) controlling how aggressive the hardening is:

        - `default`: baseline hardening — the safest starting point.
        - `compatibility`: relaxes the settings most likely to break desktop or
          uncommon hardware.
        - `performance`: relaxes settings with a performance cost.
        - `maximum`: enables every optional protection.

        For a list, presets later in the list take priority. Fine-grained
        overrides beyond the preset go through {option}`nix-mineral.settings`
        and {option}`nix-mineral.extras` directly.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    nix-mineral = {
      enable = mkDefault true;
      preset = mkDefault cfg.preset;

      # Kicksecure's generic-machine-id gives EVERY host the same static
      # machine-id (b08dfa60…) via a read-only environment.etc entry. That
      # defeats itera's requirement of a unique, persisted per-host machine-id
      # and collides with impermanence's writable /persist bind mount (forcing
      # systemd into the transient-overmount + failing commit path). Opt itera
      # into unique per-host ids; a host wanting the generic id back can flip it.
      settings.etc.generic-machine-id = mkDefault false;

      # Keep 32-bit (i686) execution working system-wide. nix-mineral's
      # `system.multilib` defaults to false, which sets `ia32_emulation=0` and
      # disables the 32-bit syscall path on 6.7+ kernels — every i686 binary,
      # including Nix's own i686 builders, then fails with "Exec format error".
      # That makes it impossible to *build* any config pulling in 32-bit closures
      # (e.g. itera.gaming's Steam) on a running itera host: a bootstrap deadlock,
      # since the kernel can't run the i686 builders needed to produce the very
      # system that would re-enable them. Keep multilib on by default so 32-bit
      # always works; a host wanting the tighter default can flip it back off.
      settings.system.multilib = mkDefault true;

      # Known benign boot-log noise from this layer — left as-is on purpose
      # (see docs/known-boot-log-noise.md for the full triage):
      #
      #   • `udev-worker: Error running install command
      #     '/usr/bin/disabled-*-by-security-misc' … retcode 127` (thunderbolt,
      #     intel_wmi_thunderbolt, pmt_class). Kicksecure's module blacklist
      #     (`settings.etc.kicksecure-module-blacklist`) disables modules via a
      #     `/usr/bin/…` path that doesn't exist on NixOS. It still fails CLOSED —
      #     the module never loads — so the hardening intent holds; the error is
      #     cosmetic. Flip that toggle off if you ever want to re-implement the
      #     blacklist natively via `boot.blacklistedKernelModules`.
      #   • `jitterentropy.service.d/overrides.conf: Failed to parse LimitMEMLOCK=`.
      #     A nixpkgs/systemd double-definition (an empty reset line followed by
      #     the real `LimitMEMLOCK=2M`, which does apply). Report upstream rather
      #     than force-overriding it here.
      #   • `systemd-sysctl: Couldn't write '0' to 'fs/binfmt_misc/status'`.
      #     `settings.kernel.binfmt-misc = false` writes the sysctl to keep
      #     binfmt_misc off; the write only fails because the fs isn't mounted, so
      #     the intent holds. Do NOT flip binfmt-misc on to silence it — that
      #     weakens hardening.
    };
  };
}
