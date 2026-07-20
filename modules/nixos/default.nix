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

  # Curated-program registrations. Each contributes a `systemModule` (the
  # system-wide `itera.programs.<app>` defaults, spliced in below) and a
  # `usersSubmodule` (the per-user `itera.users.<name>.programs.<app>` overrides,
  # spliced into the account submodule by modules/nixos/core/users.nix).
  programRegistrations = import ../programs { inherit lib iteraLib; };
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
      # DankMaterialShell: desktop shell, plus the dank-greeter greeter it was
      # split into upstream (together power `itera.desktop.dankMaterialShell`).
      inputs.dms.nixosModules.dank-material-shell
      inputs.dank-greeter.nixosModules.default
      # lanzaboote: Secure Boot & measured boot (powers `itera.secureBoot`).
      inputs.lanzaboote.nixosModules.lanzaboote
      # agenix: declarative age secrets (powers `itera.secrets`).
      inputs.agenix.nixosModules.default
      # nixos-facter: declarative hardware detection (powers `itera.hardware.facter`).
      inputs.nixos-facter-modules.nixosModules.facter
      # nix-index-database: prebuilt nix-index DB + comma (powers `itera.nixIndex`).
      inputs.nix-index-database.nixosModules.nix-index
      # nix-flatpak: declarative Flatpak (powers `itera.desktop.flatpak`).
      inputs.nix-flatpak.nixosModules.nix-flatpak
    ]
    # Auto-import every itera system feature/profile module.
    ++ iteraLib.modules.listNixModules ./.
    # Curated-program system-wide default options (`itera.programs.<app>`).
    ++ map (r: r.systemModule) programRegistrations;

  config = {
    # Register itera's per-user home collection with hjem for every user.
    hjem.extraModules = [ inputs.self.hjemModules.default ];

    # Expose iteraLib to every auto-imported feature module (mirrors the hjem
    # layer's `_module.args.iteraLib` in modules/hjem/default.nix), so a module
    # needing the mango keybind DSL / module helpers takes `iteraLib` as an arg
    # instead of re-importing ../../../lib by hand.
    _module.args.iteraLib = iteraLib;

    # Expose the flake `inputs` to the auto-imported feature modules (which
    # otherwise only receive `{ config, lib, pkgs, ... }`). A few batteries need a
    # package that lives in a flake input rather than nixpkgs — e.g. the agenix
    # CLI — and reach it via this arg.
    _module.args.iteraInputs = inputs;
  };
}
