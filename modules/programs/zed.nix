# Curated-program registration for Zed (the editor battery's home config).
#
# Declares Zed's curated settings ONCE and exposes them at two levels:
#   - `itera.programs.zed.*`               — system-wide default for every user
#   - `itera.users.<name>.programs.zed.*`  — per-user override (wins per key)
#
# The hjem battery `modules/hjem/programs/zed.nix` reads the merged result via
# `osConfig` and writes `~/.config/zed/settings.json`.
#
# See lib/programs.nix for the framework. NOT a NixOS module — a registration
# record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.modules) mkDefault;
  inherit (lib.types) attrsOf anything;
in
iteraLib.programs.mkCuratedProgram {
  name = "zed";

  fields = {
    settings = {
      type = attrsOf anything;
      attrs = true;
      example = {
        vim_mode = true;
        buffer_font_size = 14;
      };
      description = ''
        Zed settings, written to {file}`$XDG_CONFIG_HOME/zed/settings.json`. The
        system-wide default ({option}`itera.programs.zed.settings`) and each
        per-user override merge per key. itera's only opinionated default is
        disabling telemetry.
      '';
    };
  };

  # Opinionated "batteries-included" default: telemetry off (matching itera's
  # privacy-focused stack). Per-key mkDefault so explicit values override.
  systemConfig = _: {
    settings.telemetry = {
      diagnostics = mkDefault false;
      metrics = mkDefault false;
    };
  };
}
