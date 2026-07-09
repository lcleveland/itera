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
    };
  };
}
