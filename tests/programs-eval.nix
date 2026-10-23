# Evaluation check for `mkCuratedProgram`'s `resolve` (lib/programs.nix).
#
# Drives the framework with a toy schema (a scalar, an attrs field, a field with
# a merge hook and two per-user-only knobs, one nested) in a bare module system,
# so it reads no real registration and no lib constants. Checks an itera user
# with overrides, an itera user without, a plain user and the system level.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkCheckDrv
    ;
  inherit (lib) mkOption types;

  toy = (import ../lib/programs.nix { inherit lib; }).mkCuratedProgram {
    name = "toy";
    fields = {
      colour = {
        type = types.str;
        default = "red";
        description = "A scalar.";
      };
      opts = {
        type = types.attrsOf types.int;
        attrs = true;
        description = "An attrs field.";
      };
      binds = {
        type = types.attrsOf types.str;
        attrs = true;
        description = "An attrs field with a merge hook.";
        merge =
          {
            system,
            user,
            knobs,
          }:
          lib.optionalAttrs knobs.keepDefaults system // user;
      };
    };
    systemConfig = _: {
      opts = {
        a = 1;
        b = 2;
      };
      binds.x = "sys";
    };
    userExtra = {
      keepDefaults = mkOption {
        type = types.bool;
        default = true;
      };
      nested.depth = mkOption {
        type = types.int;
        default = 3;
      };
    };
  };

  osConfig =
    (lib.evalModules {
      modules = [
        toy.systemModule
        {
          options.itera.users = mkOption {
            type = types.attrsOf (types.submodule toy.usersSubmodule);
            default = { };
          };
          config.itera.users = {
            alice.programs.toy = {
              colour = "blue";
              opts.b = 20;
              binds.y = "alice";
              keepDefaults = false;
              nested.depth = 7;
            };
            bob = { };
          };
        }
      ];
    }).config;

  resolve = toy.resolve osConfig;
  defaults = {
    colour = "red";
    opts = {
      a = 1;
      b = 2;
    };
    binds.x = "sys";
    keepDefaults = true;
    nested.depth = 3;
  };
in
mkCheckDrv "itera-programs-eval" {
  "an itera user's overrides resolve" =
    resolve "alice" == {
      colour = "blue";
      opts = {
        a = 1;
        b = 20;
      };
      binds.y = "alice";
      keepDefaults = false;
      nested.depth = 7;
    };
  "an itera user without overrides gets the defaults" = resolve "bob" == defaults;
  "a plain user gets the defaults" = resolve "carol" == defaults;
  "null is the system level" = resolve null == defaults;
}
