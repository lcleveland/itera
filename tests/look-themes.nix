# Build check for the look's icon and cursor themes (wired in flake/checks.nix,
# not an eval): the theme names the tokens default to exist in the packages they
# default to, and Papirus has its teal folders. Reads both from an evaluated
# config, so the defaults live only in lib/look.nix.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  cfg =
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    }).mkConfig
      [ ];
  inherit (cfg.itera.look) icons cursor;
  dirs =
    theme: lib.concatMapStrings (n: "${theme.package}/share/icons/${n} ") (lib.attrValues theme.name);
in
pkgs.runCommand "itera-look-themes" { } ''
  for d in ${dirs icons} ${dirs cursor}; do
    test -d "$d" || { echo "missing theme $d"; exit 1; }
  done
  for n in ${lib.concatStringsSep " " (lib.attrValues icons.name)}; do
    folder=$(readlink ${icons.package}/share/icons/$n/48x48/places/folder.svg)
    case "$folder" in *teal*) ;; *) echo "$n folders are not teal: $folder"; exit 1 ;; esac
  done
  touch $out
''
