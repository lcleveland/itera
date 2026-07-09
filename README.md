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
          ./hardware-configuration.nix
          itera.nixosModules.default # pulls in hjem + wires itera's home layer
          {
            nixpkgs.overlays = [ itera.overlays.default ];
            itera.enable = true;
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
[impermanence](https://github.com/nix-community/impermanence) and
[nix-mineral](https://github.com/cynicsketch/nix-mineral) — unlike hjem these
are plain NixOS modules, so you do **not** add them as inputs or `follows` them.

### Core system defaults

Setting `itera.enable = true` turns on the opinionated **core-boot** batteries —
enough, together with a real `hardware-configuration.nix`, to boot and rebuild a
machine:

| Option namespace   | Provides                                                              |
| ------------------ | --------------------------------------------------------------------- |
| `itera.boot`       | systemd-boot on the ESP, systemd initrd, `/tmp` on tmpfs, kernel pick |
| `itera.nix`        | flakes enabled, unfree allowed, pinned `system.stateVersion`          |
| `itera.locale`     | time zone, system locale (all `LC_*`), NTP time sync                  |
| `itera.networking` | hostname, NetworkManager                                              |
| `itera.hardening`  | nix-mineral system hardening (kernel/network sysctls, lockdown, …)    |

Every value is a `mkDefault`, so override any of them individually:

```nix
{
  itera.enable = true;

  itera.networking.hostName = "myhost";
  itera.locale.timeZone = "Europe/London";
  itera.nix.stateVersion = "25.05"; # set ONCE at install time
}
```

itera does **not** manage user accounts yet — declare your login user the normal
NixOS way (`users.users.<name>`). Machine-specific pieces (`hardware-configuration.nix`,
the `itera.disko` device, real passwords) always come from your own config.

### Disk layout & ephemeral root

`itera.disko` declares your partitioning and `itera.impermanence` runs an
ephemeral (tmpfs) root that only keeps explicitly-persisted paths across reboots.
They are independent — use either alone — but compose into a full impermanent
host:

```nix
{
  # A GPT layout: ESP + a btrfs partition with /, /nix and /persist subvolumes.
  # WARNING: disko destroys everything on `device` when it formats.
  itera.disko = {
    enable = true;
    device = "/dev/nvme0n1";
  };

  # Root in RAM, wiped every boot; persist only what you name (plus itera's
  # curated defaults: logs, machine-id, SSH host keys).
  itera.impermanence = {
    enable = true; # method defaults to "tmpfs"
    directories = [ "/var/lib/tailscale" ];
    users.alice.directories = [ ".ssh" ];
  };
}
```

### Hardening

`itera.hardening` layers [nix-mineral](https://github.com/cynicsketch/nix-mineral)
onto the system. It is **opt-out**: on automatically with `itera.enable`, using
nix-mineral's baseline `default` preset. Turn it off, or dial the intensity, via:

```nix
{
  itera.enable = true;

  # Opt out entirely:
  itera.hardening.enable = false;

  # …or pick a stronger/looser preset (single value or an ordered list):
  itera.hardening.preset = "compatibility";

  # Fine-grained overrides go straight to the bundled nix-mineral options
  # (see the nix-mineral docs for the full settings/extras/filesystems trees):
  # nix-mineral.settings.<category>.<option> = …;
}
```

Baseline is intentionally conservative, but hardening can still interfere with
unusual hardware or software — reach for the `compatibility` preset (or a targeted
`nix-mineral.settings.*` override) if something breaks.

> **You must `follows` hjem.** itera's home modules are class-`hjem` submodules
> evaluated against your hjem. If itera and your config resolve to different
> hjem revisions, evaluation fails. `inputs.hjem.follows = "hjem"` keeps them in
> sync — this is the most common source of breakage.

## Structure

| Path                  | Purpose                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------- |
| `flake.nix`           | flake-parts entry point; inputs + module imports                                            |
| `flake/`              | flake outputs, dev shell + formatter, checks                                                |
| `lib/`                | helpers (module auto-import)                                                                |
| `modules/nixos/`      | system layer — `itera.*` NixOS options → `nixosModules.default`                             |
| `modules/nixos/core/` | core batteries: `boot`, `nix`, `locale`, `networking`, `disko`, `impermanence`, `hardening` |
| `modules/hjem/`       | home layer — per-program modules → `hjemModules.default`                                    |
| `overlays/`           | `pkgs.itera.*` overlay                                                                      |
| `pkgs/`               | itera's own packages                                                                        |
| `templates/`          | downstream starter flake                                                                    |
| `tests/`              | NixOS VM test harness for modules                                                           |

Adding a module is wiring-free: drop a `.nix` file into `modules/nixos/` or
`modules/hjem/` and the auto-importer (`lib/modules.nix`) picks it up. Files
prefixed with `_` (e.g. `modules/hjem/programs/_example.nix`, the reference
template) are skipped.

## Exported outputs

`nixosModules.default`, `hjemModules.default`, `overlays.default`, `lib`,
`templates.default`, plus per-system `devShells`, `formatter`, `packages`, and
`checks`.

## Development

```sh
nix develop        # shell with nil, nixfmt, statix, deadnix (installs pre-commit hook)
nix fmt            # format via treefmt (nixfmt-rfc-style + statix + deadnix + prettier)
nix flake check    # formatting + pre-commit + module tests
nix flake show     # inspect exported outputs
```

## License

Licensed under the [Apache License 2.0](LICENSE).
