# REFERENCE ONLY — this file is `_`-prefixed so it is NOT auto-imported.
#
# It documents the convention every itera "battery" (curated per-program home
# module) follows. A curated program is now TWO pieces:
#
#   1. A registration `modules/programs/<app>.nix` that declares the curated
#      options ONCE via `iteraLib.programs.mkCuratedProgram`. The framework exposes
#      them at two levels — system-wide `itera.programs.<app>.*` (default for every
#      user) and per-user `itera.users.<name>.programs.<app>.*` (wins per key). See
#      lib/programs.nix and `modules/programs/mango.nix` for a worked example.
#
#   2. A RENDERER here in `modules/hjem/programs/<app>.nix` (this file's location)
#      that reads the merged result out of `osConfig` and writes the actual $HOME
#      files. It declares NO options — the schema lives in the registration.
#
# A battery with no user-facing options (e.g. a static file gated on a system
# toggle, like `itera.nix` for the carapace spec) skips step 1 and is just a
# renderer.
#
# Reminder: this module runs inside the hjem user submodule, so the sinks
# (`packages`, `xdg.config.files`, `environment.sessionVariables`, …) are written
# unprefixed, and `name` is the username. Available module args include `config`,
# `lib`, `pkgs`, `osConfig`, `osOptions`, `hjem-lib`, `utils`, and `iteraLib`.
#
# ── The registration (put in modules/programs/example.nix) ──────────────────
#
#   { lib, iteraLib }:
#   iteraLib.programs.mkCuratedProgram {
#     name = "example";
#     fields = {
#       # attrs option: system // per-user, merged per key.
#       settings = {
#         type = lib.types.attrsOf lib.types.anything;
#         attrs = true;
#         description = "Written to $XDG_CONFIG_HOME/example/config.toml.";
#       };
#       # scalar option: per-user (nullOr) value wins when set, else the system default.
#       theme = {
#         type = lib.types.str;
#         default = "itera";
#         description = "Colour theme.";
#       };
#     };
#     # Opinionated system-wide defaults (per-key mkDefault so users override).
#     systemConfig = _: { settings.greeting = lib.mkDefault "hei"; };
#   }
#
# ── The renderer (this file's shape) ────────────────────────────────────────
{
  lib,
  pkgs,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  # Structured settings serialised with nixpkgs' format generators.
  toml = pkgs.formats.toml { };

  # Enablement follows the matching system battery toggle.
  enable = osConfig.itera.desktop.example.enable or false;

  # Merge the system-wide defaults with this user's overrides (a plain,
  # non-`itera.users` user simply has no overrides and inherits the defaults).
  sys = osConfig.itera.programs.example or { };
  usr = osConfig.itera.users.${name}.programs.example or { };

  finalSettings = (sys.settings or { }) // (usr.settings or { });
  theme = if (usr.theme or null) != null then usr.theme else (sys.theme or "itera");
in
{
  config = mkIf enable {
    # hjem sink: per-user session variables.
    environment.sessionVariables.EXAMPLE_THEME = theme;

    # hjem sink: an XDG config file generated from the merged settings.
    xdg.config.files."example/config.toml" = mkIf (finalSettings != { }) {
      source = toml.generate "example-config.toml" finalSettings;
      clobber = true;
    };
  };
}
