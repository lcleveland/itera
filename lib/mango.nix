# mango (MangoWC) keybind helpers for itera.
#
# Provides the shared keybind *type* and a renderer that turns a set of
# structured keybind declarations into the `key=value` lines mango expects in
# {file}`$XDG_CONFIG_HOME/mango/config.conf`.
#
# The same `keybindType` is consumed by two option declarations of different
# module classes — the system option `itera.desktop.mango.keybinds` (NixOS
# class) and the per-user option `itera.programs.mango.keybinds` (hjem class).
# `lib.types.submodule` is class-agnostic, so a single shared value is fine; do
# NOT pin `_class` on it.
{ lib }:
let
  inherit (lib) concatStringsSep mapAttrsToList;

  # A MangoWC bind directive. Its config key is `bind` plus any flag letters, so
  # a bind with `flagModifiers = [ "s" ]` renders under the key `binds`.
  #
  #   <bind-key>=<MOD+MOD>,<key>,<command>,<arguments>
  #
  # with an empty modifier list rendered as the literal `none` and a null
  # argument rendered as the empty string. Mirrors MangoWC's config syntax.
  keybindType = lib.types.submodule (_: {
    options = {
      modifierKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "SUPER"
          "SHIFT"
        ];
        description = "Modifier keys joined with `+` (e.g. `[ \"SUPER\" \"SHIFT\" ]`). Empty renders as `none`.";
      };

      keySymbol = lib.mkOption {
        type = lib.types.str;
        example = "Return";
        description = "Key symbol such as `Return`, `q`, or `space`.";
      };

      mangoCommand = lib.mkOption {
        type = lib.types.str;
        example = "spawn";
        description = "MangoWC command (e.g. `spawn`, `killclient`, `quit`, `spawn_shell`).";
      };

      commandArguments = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "foot";
        description = "Optional command arguments. `null` renders as the empty string.";
      };

      flagModifiers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "l"
            "r"
            "s"
            "p"
          ]
        );
        default = [ ];
        example = [ "s" ];
        description = "MangoWC bind flags appended to the `bind` key: l (lock), r (release), s (keysym), p (pass).";
      };
    };
  });

  # Render a single keybind into its `<bind-key>=<value>` line. Optional fields
  # fall back with `or` so the helper also works on plain (non-submodule) attrs.
  mkBindLine =
    kb:
    let
      flags = kb.flagModifiers or [ ];
      modifierKeys = kb.modifierKeys or [ ];
      commandArguments = kb.commandArguments or null;
      bindKey = "bind" + lib.concatStrings flags;
      modifiers = if modifierKeys == [ ] then "none" else concatStringsSep "+" modifierKeys;
      arguments = if commandArguments == null then "" else commandArguments;
    in
    "${bindKey}=${modifiers},${kb.keySymbol},${kb.mangoCommand},${arguments}";

  # Render a name-keyed attrset of keybinds into config.conf lines (one per
  # bind). The names are organisational only — they never reach the file.
  renderKeybinds = keybinds: concatStringsSep "\n" (mapAttrsToList (_: mkBindLine) keybinds);
in
{
  inherit keybindType mkBindLine renderKeybinds;
}
