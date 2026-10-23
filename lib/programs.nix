# Framework for itera's curated per-program options.
#
# A "curated program" is an application whose user-facing options itera exposes
# ONCE and makes settable at two levels:
#
#   - system-wide default for every user:  `itera.programs.<app>.*`
#   - per-user override:                    `itera.users.<name>.programs.<app>.*`
#
# with the per-user value overriding the system-wide default PER KEY. The matching
# hjem battery (`modules/hjem/programs/<app>.nix`) calls `resolve osConfig name`
# and renders the result into the user's $HOME.
#
# `mkCuratedProgram` takes a single field schema and returns the two module
# fragments that declare those option sites, so the curated schema is written
# once and adding a program is a single declaration (drop a file in
# `modules/programs/`). The system fragment lands in the NixOS module tree; the
# per-user fragment is spliced into the `itera.users.<name>` submodule.
#
# `resolve osConfig name` promises the user's resolved settings: a flat attrset
# of every field merged system-over-user, plus every per-user-only knob. A plain
# user (no `itera.users.<name>` entry) resolves exactly like an itera user with
# no overrides, and `name = null` gives the system level the same way.
{ lib }:
let
  inherit (lib.options) mkOption;
  inherit (lib.types) nullOr;
  inherit (lib.attrsets) mapAttrs optionalAttrs setAttrByPath;
in
{
  # Build the option fragments for one curated program.
  #
  #   name           the <app> key, e.g. "mango".
  #   path ?         where the options live under `itera` and `itera.users.<name>`,
  #                  default `[ "programs" name ]`. The look uses `[ "look" ]`.
  #   fields         attrset  fieldName -> {
  #                    type;                # nix option type
  #                    attrs ? false;       # true = attrs option merged per-key with
  #                                         #   `system // user`; false = scalar/list,
  #                                         #   per-user (nullOr) value wins when set.
  #                    default ? …;         # STATIC system-wide default. Required for
  #                                         #   scalar fields; attrs fields default {}.
  #                    description;
  #                    example ? …; defaultText ? …;
  #                    merge ? { system, user, knobs }: …;  # replaces the default
  #                                         #   merge; `knobs` are the user's
  #                                         #   resolved per-user-only options.
  #                  }
  #                  These fields exist at BOTH levels (system default + per-user).
  #   systemConfig ? config: -> attrset of COMPUTED system-wide defaults for `fields`,
  #                  merged into `itera.programs.<name>` (e.g. mango's assembled
  #                  keybind set, which depends on `config.itera.desktop.mango.commands`).
  #                  Wrap values in `mkDefault`/per-key `mkDefault` yourself so consumers
  #                  can override them.
  #   userExtra ?    attrset of EXTRA per-user-only options (raw mkOption values) that
  #                  have no system-wide counterpart — e.g. mango `autostart`,
  #                  `extraConfig`, `defaultKeybinds.enable`; dms `clobber`; a per-user
  #                  `enable`. The renderer reads these straight off the per-user value.
  mkCuratedProgram =
    {
      name,
      path ? [
        "programs"
        name
      ],
      fields,
      systemConfig ? (_: { }),
      userExtra ? { },
    }:
    let
      mkFieldOption =
        f: extra:
        mkOption (
          {
            inherit (f) type description;
          }
          // extra
          // optionalAttrs (f ? example) { inherit (f) example; }
          // optionalAttrs (f ? defaultText) { inherit (f) defaultText; }
        );

      # System-wide options: real types; attrs default {}, scalars take their
      # static `default` (computed defaults are supplied via `systemConfig`).
      systemOptions = mapAttrs (
        _: f: mkFieldOption f { default = if f.attrs or false then { } else f.default; }
      ) fields;

      # Per-user options: attrs default {} ("no override"); scalars widen to
      # `nullOr` defaulting to null ("inherit the system-wide value").
      userFieldOptions = mapAttrs (
        _: f:
        if f.attrs or false then
          mkFieldOption f { default = { }; }
        else
          mkOption {
            type = nullOr f.type;
            default = null;
            description = f.description + " Per-user override; `null` inherits the system-wide default.";
          }
      ) fields;

      # The per-user value of a plain user: no definitions, so fields are null
      # (or {}) and knobs take their defaults. Bound once per registration.
      plainUser = lib.getAttrFromPath path (lib.evalModules { modules = [ usersSubmodule ]; }).config;

      usersSubmodule = {
        options = setAttrByPath path (userFieldOptions // userExtra);
      };
    in
    {
      inherit name usersSubmodule;

      resolve =
        osConfig: user:
        let
          system = lib.getAttrFromPath path osConfig.itera;
          own = if user == null then null else osConfig.itera.users.${user} or null;
          usr = if own == null then plainUser else lib.getAttrFromPath path own;
          knobs = lib.getAttrs (lib.attrNames userExtra) usr;
        in
        knobs
        // mapAttrs (
          n: f:
          if f ? merge then
            f.merge {
              system = system.${n};
              user = usr.${n};
              inherit knobs;
            }
          else if f.attrs or false then
            system.${n} // usr.${n}
          else if usr.${n} != null then
            usr.${n}
          else
            system.${n}
        ) fields;

      # Splice into the NixOS module tree: the system-wide default level.
      systemModule =
        { config, ... }:
        {
          options.itera = setAttrByPath path systemOptions;
          config.itera = setAttrByPath path (systemConfig config);
        };
    };
}
