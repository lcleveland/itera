# itera's system-level NixOS module.
#
# Closes over the flake `inputs` so it can (a) pull hjem into the consumer's
# configuration and (b) auto-register itera's per-user home layer into
# `hjem.extraModules`. This is the "batteries-included" wiring: a consumer
# imports THIS module alone and gets both the system options and the hjem
# home collection.
inputs:
{ lib, ... }:
let
  iteraLib = import ../../lib { inherit lib; };
in
{
  imports =
    # Pull hjem in so the consumer does not have to import it separately.
    [ inputs.hjem.nixosModules.default ]
    # Auto-import every itera system feature/profile module (none yet).
    ++ iteraLib.modules.listNixModules ./.;

  # Register itera's per-user home collection with hjem for every user.
  config.hjem.extraModules = [ inputs.self.hjemModules.default ];
}
