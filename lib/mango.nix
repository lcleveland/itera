# mango (MangoWC) keybind helpers for itera.
#
# Provides the shared keybind *type* and a renderer that turns a set of
# structured keybind declarations into the `key=value` lines mango expects in
# {file}`$XDG_CONFIG_HOME/mango/config.conf`.
#
# The same `keybindType` is consumed by both levels of the curated mango options
# — the system-wide default `itera.programs.mango.keybinds` and the per-user
# `itera.users.<name>.programs.mango.keybinds` (both NixOS class, generated once
# by the curated-program framework). `lib.types.submodule` is class-agnostic, so a
# single shared value is fine; do NOT pin `_class` on it.
{ lib }:
let
  inherit (lib) concatStringsSep mapAttrsToList;

  # MangoWC's built-in tiling layouts (see mango's docs/window-management/layouts).
  # Used to build the `enum` type for the layout options in both mango batteries.
  supportedLayouts = [
    "tile"
    "scroller"
    "monocle"
    "grid"
    "deck"
    "center_tile"
    "vertical_tile"
    "right_tile"
    "vertical_scroller"
    "vertical_grid"
    "vertical_deck"
    "dwindle"
    "fair"
    "vertical_fair"
  ];

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

  # MangoWC has no single "default layout" key — the startup layout is set per
  # tag via `tagrule=id:N,layout_name:<layout>`. Render one such line per tag to
  # give every tag the same default. `tagCount` defaults to 9 to match itera's
  # `SUPER+1..9` tag binds (see `tags` in modules/nixos/desktop/mango.nix); keep
  # the two in sync.
  mkTagLayoutLines =
    {
      layout,
      tagCount ? 9,
    }:
    concatStringsSep "\n" (
      map (id: "tagrule=id:${toString id},layout_name:${layout}") (lib.range 1 tagCount)
    );

  # Render the `circle_layout=` line that `switch_layout` cycles through. An
  # empty list renders as "" so the line is omitted entirely (mango then cycles
  # all built-in layouts).
  mkCircleLayoutLine =
    layouts: if layouts == [ ] then "" else "circle_layout=${concatStringsSep "," layouts}";
in
{
  inherit
    keybindType
    mkBindLine
    renderKeybinds
    supportedLayouts
    mkTagLayoutLines
    mkCircleLayoutLine
    ;
}
