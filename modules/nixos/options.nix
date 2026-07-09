{ lib, ... }:
{
  # Master switch for itera's opinionated system defaults. Feature/profile
  # modules (added later) guard their `config` on `config.itera.enable` and use
  # `lib.mkDefault`, so every curated default stays opt-out.
  options.itera.enable = lib.mkEnableOption "itera opinionated system defaults";
}
