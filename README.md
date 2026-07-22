# itera

A curated, **batteries-included** Nix configuration layer you import into your
own flake. Enable it and get an opinionated, sane-defaults experience — with
every default **opt-out**.

itera does **not** use home-manager. `$HOME`/dotfile management is built on
[hjem](https://github.com/feel-co/hjem), and itera provides its own
configuration-management module layer on top of it.

## Requirements

[Nix](https://nixos.org/download.html) with flakes enabled:

```
experimental-features = nix-command flakes
```

## Usage

Scaffold a new configuration from the template:

```sh
nix flake init -t github:lcleveland/itera
```

Or wire itera into an existing flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    hjem.url = "github:feel-co/hjem";
    itera = {
      url = "github:lcleveland/itera";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.hjem.follows = "hjem"; # CRITICAL — see note below
    };
  };

  outputs =
    { nixpkgs, itera, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # No hardware-configuration.nix — itera supplies the hardware layer
          # (`itera.hardware`) and disko owns the disk layout (`itera.disko`).
          itera.nixosModules.default # pulls in hjem + wires itera's home layer
          {
            nixpkgs.overlays = [ itera.overlays.default ];
            # itera.enable defaults to true — the whole opinionated layer is
            # opt-out. disko/impermanence are on by default too; disko wipes a
            # disk and has no safe default, so point it at your target device
            # (the build asserts until you do).
            itera.disko.device = "/dev/nvme0n1"; # CHANGE ME — disko WIPES this disk
            itera.hardware.cpu = "auto"; # or "intel" / "amd"
            hjem.users.alice.enable = true;
            # curated program modules plug in under `hjem.users.<name>.itera.*`
          }
        ];
      };
    };
}
```

Importing `itera.nixosModules.default` is all you need: it imports hjem for you
and registers itera's per-user home collection into `hjem.extraModules`. It also
bundles [disko](https://github.com/nix-community/disko),
[impermanence](https://github.com/nix-community/impermanence),
[nix-mineral](https://github.com/cynicsketch/nix-mineral),
[lanzaboote](https://github.com/nix-community/lanzaboote),
[agenix](https://github.com/ryantm/agenix),
[nixos-facter](https://github.com/nix-community/nixos-facter-modules),
[nix-index-database](https://github.com/nix-community/nix-index-database) and
[nix-flatpak](https://github.com/gmodena/nix-flatpak) — unlike hjem these are
plain NixOS modules, so you do **not** add them as inputs or `follows` them.

> **You must `follows` hjem.** itera's home modules are class-`hjem` submodules
> evaluated against your hjem. If itera and your config resolve to different
> hjem revisions, evaluation fails. `inputs.hjem.follows = "hjem"` keeps them in
> sync — this is the most common source of breakage.

## Documentation

The full configuration reference lives in the
[**wiki**](https://github.com/lcleveland/itera/wiki):

- [Core system defaults](https://github.com/lcleveland/itera/wiki/Core-System-Defaults)
  — the opt-out core-boot batteries (`itera.boot`/`hardware`/`nix`/`locale`/…)
  and `itera.nix.cache`.
- [Disks & impermanence](https://github.com/lcleveland/itera/wiki/Disks-and-Impermanence)
  — the `itera.disko` layout (and its required device), opt-in LUKS full-disk
  encryption (`itera.disko.encryption`) with optional passwordless TPM2 auto-unlock
  (`itera.disko.encryption.tpm2`), and the ephemeral tmpfs root.
- [Hardening](https://github.com/lcleveland/itera/wiki/Hardening)
  — nix-mineral presets and overrides.
- [Desktop](https://github.com/lcleveland/itera/wiki/Desktop)
  — mango + DankMaterialShell, monitors, and per-user program config.
- [Ecosystem integrations](https://github.com/lcleveland/itera/wiki/Ecosystem-Integrations)
  — secrets, virtualisation, secure boot, flatpak, facter, NVIDIA, security keys,
  fingerprint, and nixos-hardware.
- [Installation](https://github.com/lcleveland/itera/wiki/Installation)
  — installing from a live ISO and the `itera-testhost`.
- [The `itera` command](https://github.com/lcleveland/itera/wiki/The-itera-Command)
  — the on-system CLI (`rebuild`, `update`, `gc`, `facter report`).
- [Repository structure](https://github.com/lcleveland/itera/wiki/Repository-Structure)
  — repository layout and exported outputs.

## Development

```sh
nix develop        # shell with nil, nixfmt, statix, deadnix (installs pre-commit hook)
nix fmt            # format via treefmt (nixfmt-rfc-style + statix + deadnix + prettier)
nix flake check    # formatting + pre-commit + module tests
nix flake show     # inspect exported outputs
```

## License

Licensed under the [Apache License 2.0](LICENSE).
