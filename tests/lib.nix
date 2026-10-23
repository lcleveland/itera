# Shared scaffolding for itera's `*-eval` checks.
#
# Every eval check builds a NixOS configuration on top of
# `self.nixosModules.default` and then asserts things about the generated
# `config`. This module factors out the two pieces they all repeated:
#
#   - `mkConfig`: evaluate a config with itera on and a pinned stateVersion,
#     returning `.config`. disko + impermanence are defaulted OFF (via
#     `mkDefault`) since most checks don't want a device assertion / tmpfs root;
#     a check that needs them (see disko-impermanence-eval.nix,
#     integrations-eval.nix) turns them on with `diskoOn` below.
#   - `diskoOn`: the module that flips disko + impermanence back on, with a
#     device set. Shared so the two checks that need it can't drift apart.
#   - `hasPkgName` / `hasPkgInfix`: the two package-list predicates the checks
#     kept redefining. They are NOT interchangeable — see their notes.
#   - `mkCheckDrv`: the `failed`-attrs → `runCommand`/`throw` tail.
#   - `userFile`: the text of a user's `~/.config/<path>`.
#   - `mangoLines`: a mango config.conf parsed into ordered key/value lines.
#
# NOT a discovered check itself: flake/checks.nix imports each eval file by name,
# and tests/default.nix only scans tests/nixos/, so this helper is never run as a
# test on its own.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  # text :: mango config.conf -> [ { key; value; fields; label; } ], in order.
  # Splits on the first `=`; `value` keeps any later `=` and `fields` is `value`
  # split on commas. Blank lines are skipped; a `#` line labels the next line,
  # as DMS reads cheatsheet labels. Any other line without `=` throws.
  mangoLines =
    text:
    (lib.foldl'
      (
        acc: line:
        let
          comment = builtins.match "#[[:space:]]*(.*)" line;
          kv = builtins.match "([^=]*)=(.*)" line;
          value = lib.last kv;
        in
        if builtins.match "[[:space:]]*" line != null then
          acc
        else if comment != null then
          acc // { label = builtins.head comment; }
        else if kv == null then
          throw "mangoLines: no `=` in line: ${line}"
        else
          {
            label = null;
            lines = acc.lines ++ [
              {
                key = builtins.head kv;
                inherit value;
                fields = lib.splitString "," value;
                inherit (acc) label;
              }
            ];
          }
      )
      {
        label = null;
        lines = [ ];
      }
      (lib.splitString "\n" text)
    ).lines;
in
assert
  mangoLines "a=b=c\n\n# Open terminal\nbind=SUPER,Return,spawn,foot -e sh -c x\nk=v" == [
    {
      key = "a";
      value = "b=c";
      fields = [ "b=c" ];
      label = null;
    }
    {
      key = "bind";
      value = "SUPER,Return,spawn,foot -e sh -c x";
      fields = [
        "SUPER"
        "Return"
        "spawn"
        "foot -e sh -c x"
      ];
      label = "Open terminal";
    }
    {
      key = "k";
      value = "v";
      fields = [ "v" ];
      label = null;
    }
  ];
assert !(builtins.tryEval (builtins.deepSeq (mangoLines "no equals here") null)).success;
{
  inherit mangoLines;

  # The text of a user's `~/.config/<path>`. hjem defaults `text` to null, so
  # fall through to the `source` (IFD for store-built files such as mango's).
  # Rendered text can carry store-path context, which `builtins.fromJSON`
  # refuses; these are read-only assertions and nothing built from the result
  # reaches a derivation, so the context is discarded here.
  userFile =
    cfg: user: path:
    let
      f = cfg.hjem.users.${user}.xdg.config.files.${path};
    in
    if f.text != null then builtins.unsafeDiscardStringContext f.text else builtins.readFile f.source;

  # extraModules :: list of NixOS modules layered on top of the itera base.
  # Returns the evaluated `.config`.
  mkConfig =
    extraModules:
    (nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.default
        {
          system.stateVersion = "25.05";
          itera = {
            enable = true;
            # Off by default so disko's device assertion doesn't block evals that
            # only exercise other batteries; a check needing them sets them on.
            disko.enable = lib.mkDefault false;
            impermanence.enable = lib.mkDefault false;
          };
        }
      ]
      ++ extraModules;
    }).config;

  # Turn disko + impermanence back on (overriding mkConfig's mkDefault-off) so a
  # check exercises partitioning and the tmpfs root. Layer it into the module
  # list: `mkConfig [ diskoOn { … } ]`.
  diskoOn = {
    itera.disko = {
      enable = true;
      device = "/dev/vda";
    };
    itera.impermanence.enable = true;
  };

  # Exact match on the derivation's parsed name, e.g. `hasPkgName "git"`. Use
  # this by default — it cannot match a package by accident.
  hasPkgName = name: pkgList: builtins.elem name (map lib.getName pkgList);

  # Looser: exact `pname` OR a substring of the full name-with-version. Needed
  # where the attribute and the derivation name disagree — e.g. matching
  # a pname against a package whose attribute name differs. Prefer
  # `hasPkgName` unless a check actually needs this.
  hasPkgInfix =
    pname: pkgList:
    builtins.any (p: (p.pname or p.name or "") == pname || lib.hasInfix pname (p.name or "")) pkgList;

  # name :: derivation name, also used in the failure message.
  # checks :: attrset of <description> -> <bool>. Fails loudly listing every
  # false entry; otherwise produces an empty output.
  mkCheckDrv =
    name: checks:
    let
      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
    in
    pkgs.runCommand name { } (
      if failed == [ ] then "touch $out" else throw "${name} failed: ${lib.concatStringsSep "; " failed}"
    );
}
