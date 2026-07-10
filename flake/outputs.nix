{ inputs, lib, ... }:
{
  flake = {
    # Consumer-facing library: module auto-import helper today, generators/types later.
    lib = import ../lib { inherit lib; };

    # System-level NixOS module. Auto-imports hjem and registers itera's per-user
    # home layer into `hjem.extraModules`, so a consumer imports a SINGLE module.
    # Closes over `inputs` so it can reach hjem and `self.hjemModules.default`.
    nixosModules.itera = import ../modules/nixos inputs;
    nixosModules.default = inputs.self.nixosModules.itera;

    # Per-user home module collection, evaluated inside the hjem user submodule.
    # Consumers add this to `hjem.extraModules` (the auto-wiring above does it for them).
    hjemModules.itera = import ../modules/hjem;
    hjemModules.default = inputs.self.hjemModules.itera;

    # Per-machine hardware quirk profiles, re-exported from nixos-hardware.
    # These are import-time board selections the module system can't toggle from
    # config, so unlike itera's other bundled projects they are not auto-imported.
    # A consumer picks their board without adding nixos-hardware as their own
    # input, e.g.:
    #   imports = [ itera.nixosModules.default itera.hardwareModules.framework-13-7040-amd ];
    hardwareModules = inputs.nixos-hardware.nixosModules;

    # Package overlay (exposes `pkgs.itera.*`); passthrough until packages land.
    overlays.default = import ../overlays inputs;

    # Starter flake for new consumers: `nix flake init -t github:lcleveland/itera`.
    templates.default = {
      path = ../templates/default;
      description = "A downstream NixOS flake preconfigured to consume itera + hjem.";
    };
  };
}
