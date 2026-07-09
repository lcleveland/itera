# itera's binary-cache battery: extra substituters + their trusted public keys.
#
# Adds public binary caches on top of the built-in `cache.nixos.org` so common
# closures download prebuilt instead of compiling locally. Defaults to
# nix-community (a broad community cache); point `substituters` at any additional
# cache — including your own — to pull things nixpkgs' cache doesn't carry.
#
# Follows the opt-out shape of the other core batteries (see `hardening.nix`):
# gated on the master `itera.enable` with a per-feature `enable` (default true),
# so it comes along automatically but is fully overridable. Uses the `extra-*`
# settings so the stock `cache.nixos.org` substituter and key stay in place.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool listOf str;

  cfg = config.itera.nix.cache;
in
{
  options.itera.nix.cache = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Add itera's extra binary-cache substituters. On by default whenever
        {option}`itera.enable` is set; set this to `false` to build everything
        against only the stock caches.
      '';
    };

    substituters = mkOption {
      type = listOf str;
      default = [ "https://nix-community.cachix.org" ];
      example = [
        "https://nix-community.cachix.org"
        "https://my-cache.example.org"
      ];
      description = ''
        Extra binary-cache substituter URLs, appended to the built-in
        {command}`cache.nixos.org`. Each entry needs a matching key in
        {option}`itera.nix.cache.trustedPublicKeys`.
      '';
    };

    trustedPublicKeys = mkOption {
      type = listOf str;
      default = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
      description = ''
        Trusted public keys matching {option}`itera.nix.cache.substituters`. A
        substituter's paths are only trusted if its key is listed here.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    nix.settings = {
      extra-substituters = cfg.substituters;
      extra-trusted-public-keys = cfg.trustedPublicKeys;
    };
  };
}
