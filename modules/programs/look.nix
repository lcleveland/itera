# Registration for the itera look (`itera.look` and its per-user mirror). The
# options, palette and resolver live in lib/look.nix, the one file that reads
# them.
{ iteraLib, ... }:
iteraLib.look.registration
