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
    # Bundle the upstream modules itera builds on so the consumer imports a SINGLE
    # module and gets everything. These are inert until their options are set.
    [
      # hjem: $HOME / dotfile management.
      inputs.hjem.nixosModules.default
      # disko: declarative disk partitioning (powers `itera.disko`).
      inputs.disko.nixosModules.default
      # impermanence: ephemeral-root persistence (powers `itera.impermanence`).
      inputs.impermanence.nixosModules.impermanence
      # nix-mineral: system hardening (powers `itera.hardening`).
      inputs.nix-mineral.nixosModules.nix-mineral
      # mango: Wayland compositor (powers `itera.desktop.mango`).
      inputs.mango.nixosModules.mango
      # DankMaterialShell: desktop shell + greeter (powers `itera.desktop.dankMaterialShell`).
      inputs.dms.nixosModules.dank-material-shell
      inputs.dms.nixosModules.greeter
    ]
    # Auto-import every itera system feature/profile module.
    ++ iteraLib.modules.listNixModules ./.;

  # Register itera's per-user home collection with hjem for every user.
  config.hjem.extraModules = [ inputs.self.hjemModules.default ];
}
