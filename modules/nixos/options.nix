{ lib, ... }:
{
  # Master switch for itera's opinionated system defaults. On by default:
  # importing `nixosModules.default` gives you the full opinionated system, and
  # you disable the pieces you don't want. Feature/profile modules guard their
  # `config` on `config.itera.enable` and set values with `lib.mkDefault`, so
  # every curated default is opt-out (on, but individually overridable). Set this
  # to `false` to turn the whole layer off.
  options.itera.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to enable itera's opinionated system defaults.";
  };
}
