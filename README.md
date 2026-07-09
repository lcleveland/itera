# itera

The base of a NixOS configuration, managed as a Nix flake.

## Requirements

- [Nix](https://nixos.org/download.html) with flakes enabled. Add the following to
  your Nix config (`/etc/nix/nix.conf` or `~/.config/nix/nix.conf`):

  ```
  experimental-features = nix-command flakes
  ```

## Structure

`flake.nix` is the entry point. It exposes two nixpkgs inputs so either channel can be
used as needed:

- `nixpkgs` — the stable channel (`nixos-25.05`)
- `nixpkgs-unstable` — the rolling `nixos-unstable` channel

Hosts, packages, and dev shells are added under the flake's `outputs`.

## Usage

Once a host is defined under `nixosConfigurations`:

```sh
# Build and switch to a host configuration
sudo nixos-rebuild switch --flake .#<host>

# Update all flake inputs
nix flake update
```

## License

Licensed under the [Apache License 2.0](LICENSE).
