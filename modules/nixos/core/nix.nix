# itera's nix battery: flakes, unfree packages, and system.stateVersion.
#
# The minimum Nix-level configuration a flake-based system needs to rebuild
# itself: the `nix-command`/`flakes` experimental features, permission to pull in
# unfree firmware/drivers, and a pinned `system.stateVersion`.
#
# Gated on the master `itera.enable` with `mkDefault` values, so everything is
# opt-out and overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault mkBefore;
  inherit (lib.types) bool str;

  cfg = config.itera.nix;
in
{
  options.itera.nix = {
    flakes.enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable the {command}`nix-command` and {command}`flakes` experimental
        features so the system can be rebuilt from a flake.
      '';
    };

    allowUnfree = mkOption {
      type = bool;
      default = true;
      description = ''
        Allow unfree nixpkgs packages. Disabling this may make some hardware
        drivers or firmware unavailable.
      '';
    };

    stateVersion = mkOption {
      type = str;
      default = "25.05";
      example = "24.11";
      description = ''
        The NixOS release the system's stateful data is compatible with. Set once
        at install time and normally never changed — see
        {option}`system.stateVersion`.
      '';
    };
  };

  config = mkIf config.itera.enable {
    warnings = lib.optionals (config.system.stateVersion != cfg.stateVersion) [
      "itera.nix.stateVersion (${cfg.stateVersion}) differs from system.stateVersion (${config.system.stateVersion}). Changing stateVersion after installation can break existing systems; it should normally only be set once."
    ];

    nix.settings.experimental-features = mkIf cfg.flakes.enable (mkBefore [
      "nix-command"
      "flakes"
    ]);

    # `nixpkgs.config` is an opaque `attrs`-typed option, so a nested `mkDefault`
    # would be stored literally rather than resolved — set it plainly. Override
    # via `itera.nix.allowUnfree`, not by redefining `nixpkgs.config.allowUnfree`.
    nixpkgs.config.allowUnfree = cfg.allowUnfree;

    system.stateVersion = mkDefault cfg.stateVersion;
  };
}
