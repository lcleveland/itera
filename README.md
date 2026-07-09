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
[impermanence](https://github.com/nix-community/impermanence) and
[nix-mineral](https://github.com/cynicsketch/nix-mineral) — unlike hjem these
are plain NixOS modules, so you do **not** add them as inputs or `follows` them.

### Core system defaults

`itera.enable` defaults to `true`, so the whole layer is **opt-out**: importing
the module turns on the opinionated **core-boot** batteries — enough, on their
own, to boot and rebuild a machine with no generated `hardware-configuration.nix`
(`itera.hardware` supplies the hardware layer, `itera.disko` the disks). Set
`itera.enable = false` to turn everything off.

| Option namespace   | Provides                                                              |
| ------------------ | --------------------------------------------------------------------- |
| `itera.boot`       | systemd-boot on the ESP, systemd initrd, `/tmp` on tmpfs, kernel pick |
| `itera.hardware`   | initrd kernel modules, CPU microcode, redistributable firmware        |
| `itera.nix`        | flakes enabled, unfree allowed, pinned `system.stateVersion`          |
| `itera.nix.cache`  | extra binary-cache substituters (nix-community) for faster builds     |
| `itera.locale`     | time zone, system locale (all `LC_*`), NTP time sync                  |
| `itera.networking` | hostname, NetworkManager                                              |
| `itera.hardening`  | nix-mineral system hardening (kernel/network sysctls, lockdown, …)    |

Every value is a `mkDefault`, so override any of them individually:

```nix
{
  itera.networking.hostName = "myhost";
  itera.locale.timeZone = "Europe/London";
  itera.nix.stateVersion = "25.05"; # set ONCE at install time
}
```

`itera.nix.cache` adds extra binary-cache substituters (default:
nix-community) on top of the built-in `cache.nixos.org`, so common closures
download prebuilt. It is **opt-out**; point it at any additional cache — your own
included — to pull things nixpkgs' cache doesn't carry:

```nix
{
  # Disable entirely:
  #   itera.nix.cache.enable = false;

  # …or add your own cache (keys must line up with substituters):
  itera.nix.cache.substituters = [
    "https://nix-community.cachix.org"
    "https://my-cache.example.org"
  ];
  itera.nix.cache.trustedPublicKeys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "my-cache.example.org-1:…"
  ];
}
```

> **Note.** mango and DankMaterialShell publish no public cache, so they build
> from source on first `nixos-rebuild` until you add a substituter that hosts
> them.

The only genuinely per-machine pieces that must come from your own config are the
`itera.disko` device (destructive and un-guessable) and real passwords — there is
no `hardware-configuration.nix` to maintain. Pick a CPU vendor with
`itera.hardware.cpu` if you want (the `"auto"` default works either way).

### Disk layout & ephemeral root

`itera.disko` declares your partitioning and `itera.impermanence` runs an
ephemeral (tmpfs) root that only keeps explicitly-persisted paths across reboots.
Both are **opt-out (on by default)**, but they need per-host input:

> **You must handle disko.** With `itera.enable` on, `itera.disko` is enabled by
> default but has no default device, so it **fails the build with an assertion
> until you either set `itera.disko.device` or set `itera.disko.enable = false`**.
> disko destroys everything on `device` when it formats — never point it at a
> disk you can't lose.
>
> **Advanced — managing partitioning yourself.** For a pre-partitioned machine
> you can't wipe, or a dual-boot setup, turn off both disko and itera's hardware
> layer and add your own generated `hardware-configuration.nix` (which then
> provides the `fileSystems` and kernel modules):
>
> ```nix
> {
>   itera.hardware.enable = false;
>   itera.disko.enable = false;
>   itera.impermanence.enable = false;
> }
> ```

They are independent — use either alone — but compose into a full impermanent
host:

```nix
{
  # A GPT layout: ESP + a btrfs partition with /, /nix and /persist subvolumes.
  # WARNING: disko destroys everything on `device` when it formats.
  itera.disko.device = "/dev/nvme0n1"; # enabled by default; a device is required

  # Root in RAM, wiped every boot; persist only what you name (plus itera's
  # curated defaults: logs, machine-id, SSH host keys). On by default; method
  # defaults to "tmpfs".
  itera.impermanence = {
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

### Desktop

`itera.desktop` provides an opinionated Wayland desktop:
[mango](https://github.com/mangowm/mango) (a dwl-based wlroots compositor) running
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (a
Quickshell desktop shell), with login handled by DankMaterialShell's own greetd
greeter. Both upstreams are bundled — you do **not** add them as inputs.

| Option namespace                  | Provides                                                        |
| --------------------------------- | --------------------------------------------------------------- |
| `itera.desktop.mango`             | the mango compositor (portals, polkit, xwayland, session)       |
| `itera.desktop.dankMaterialShell` | the DMS shell + greeter; pulls in mango                         |
| `itera.programs.mango` (home)     | per-user `mango/config.conf` that autostarts DMS in the session |

Like the other opinionated defaults it is **opt-out**: on automatically with
`itera.enable`, so importing itera already gives you mango + DankMaterialShell +
the DMS greeter, all wired together. Override as needed:

```nix
{
  # Opt out of the desktop entirely (keep the rest of itera):
  #   itera.desktop.dankMaterialShell.enable = false;

  # …or keep the shell but drop the greeter and arrange login yourself:
  #   itera.desktop.dankMaterialShell.greeter.enable = false;

  # DMS's native feature toggles remain reachable (all default on):
  #   programs.dank-material-shell.enableSystemMonitoring = false;
}
```

The matching per-user config is enabled automatically for every hjem user once
`itera.desktop.mango` is on (it follows the system toggle). Add your own mango
keybinds / window rules via:

```nix
{
  hjem.users.alice.itera.programs.mango.extraConfig = ''
    bind=SUPER,Return,spawn,foot
  '';
}
```

> **Hardening caveat.** `itera.hardening` (on by default with `itera.enable`) can
> interfere with a graphical stack. If the desktop misbehaves, try
> `itera.hardening.preset = "compatibility"` or a targeted `nix-mineral.settings.*`
> override. The first `nixos-rebuild` also builds mango and DMS from source
> (wlroots/scenefx, Go + Qt), so expect a long initial build.

> **You must `follows` hjem.** itera's home modules are class-`hjem` submodules
> evaluated against your hjem. If itera and your config resolve to different
> hjem revisions, evaluation fails. `inputs.hjem.follows = "hjem"` keeps them in
> sync — this is the most common source of breakage.

## Structure

| Path                     | Purpose                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------- |
| `flake.nix`              | flake-parts entry point; inputs + module imports                                            |
| `flake/`                 | flake outputs, dev shell + formatter, checks                                                |
| `lib/`                   | helpers (module auto-import)                                                                |
| `modules/nixos/`         | system layer — `itera.*` NixOS options → `nixosModules.default`                             |
| `modules/nixos/core/`    | core batteries: `boot`, `nix`, `locale`, `networking`, `disko`, `impermanence`, `hardening` |
| `modules/nixos/desktop/` | desktop batteries: `mango` compositor, `dankMaterialShell` shell + greeter                  |
| `modules/hjem/`          | home layer — per-program modules → `hjemModules.default`                                    |
| `overlays/`              | `pkgs.itera.*` overlay                                                                      |
| `pkgs/`                  | itera's own packages                                                                        |
| `templates/`             | downstream starter flake                                                                    |
| `tests/`                 | NixOS VM test harness for modules                                                           |

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
