# Curated-program registration for nushell (the shell battery's home config).
#
# Declares nushell's curated knobs ONCE and exposes them at two levels:
#   - `itera.programs.nushell.*`               — system-wide default for every user
#   - `itera.users.<name>.programs.nushell.*`  — per-user override (wins per key)
#
# The hjem battery `modules/hjem/programs/nushell.nix` reads the merged result via
# `osConfig` and writes the per-user config under `~/.config/nushell/` (chiefly the
# carapace external-completer hookup).
#
# See lib/programs.nix for the framework. NOT a NixOS module — a registration
# record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.types) bool lines;
in
iteraLib.programs.mkCuratedProgram {
  name = "nushell";

  fields = {
    showBanner = {
      type = bool;
      default = false;
      description = "Show nushell's startup banner (`$env.config.show_banner`).";
    };

    extraEnv = {
      type = lines;
      default = "";
      description = "Arbitrary nushell appended to {file}`~/.config/nushell/env.nu`.";
    };

    extraConfig = {
      type = lines;
      default = "";
      description = ''
        Arbitrary nushell appended to {file}`~/.config/nushell/config.nu`, after
        itera's defaults and the carapace hookup. Mutate `$env.config` fields
        individually rather than reassigning the whole record.
      '';
    };
  };
}
