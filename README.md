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
| `itera.networking` | hostname, NetworkManager, stable MAC (constant IP across reboots)     |
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
  # curated defaults: logs, machine-id, SSH host keys, NetworkManager
  # connections, clock state). On by default; method defaults to "tmpfs".
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

### Ecosystem integrations

itera bundles a set of complementary NixOS projects as plain modules (no extra
inputs on your side). Each is a thin `itera.*` wrapper; the underlying upstream
options stay reachable for fine-tuning.

| Option namespace            | Provides                                                | Default |
| --------------------------- | ------------------------------------------------------- | ------- |
| `itera.secrets`             | agenix declarative secrets (decrypted to `/run/agenix`) | on\*    |
| `itera.nixIndex`            | `command-not-found` + `comma` (`,`) via a prebuilt DB   | on      |
| `itera.virtualisation`      | QEMU/KVM via libvirt (OVMF + swtpm) + virt-manager GUI  | on      |
| `itera.desktop.fileManager` | Nemo file manager (+ gvfs mounting, tumbler thumbnails) | on      |
| `itera.desktop.browser`     | ungoogled-chromium (default web handler + `SUPER+b`)    | on      |
| `itera.desktop.theme`       | dark color scheme for GTK/Flatpak apps (matches DMS)    | on      |
| `itera.secureBoot`          | Secure Boot & measured boot via lanzaboote              | off     |
| `itera.desktop.flatpak`     | declarative Flatpak (nix-flatpak, Flathub)              | off     |
| `itera.hardware.facter`     | declarative hardware detection via nixos-facter         | off     |
| `itera.nvidia`              | NVIDIA drivers (open module, container toolkit, PRIME)  | off     |

\* on, but inert until you declare a secret.

```nix
{
  # Secrets — encrypted .age files, decrypted at activation using the host SSH
  # key (which impermanence already persists):
  itera.secrets.secrets.wifi-psk.file = ./secrets/wifi-psk.age;

  # Virtualization — give your user libvirt access and pick a CPU for KVM:
  itera.hardware.cpu = "amd";
  itera.users.alice.extraGroups = [ "wheel" "networkmanager" "libvirtd" ];

  # Opt-in batteries:
  itera.desktop.flatpak = {
    enable = true;
    packages = [ "com.brave.Browser" ];
  };
  itera.hardware.facter.reportPath = ./facter.json; # generate per host, see below
}
```

**Secure Boot** is the one deliberately opt-_in_ battery — it needs a one-time
key enrollment with the firmware in setup mode, so it cannot be safely defaulted:

```nix
{ itera.secureBoot.enable = true; }
```

```sh
sudo sbctl create-keys                 # generate keys (persisted at /var/lib/sbctl)
sudo sbctl enroll-keys --microsoft     # firmware must be in setup mode
sudo nixos-rebuild switch && reboot
bootctl status                         # verify Secure Boot is active
```

Enabling it swaps systemd-boot for lanzaboote. **nixos-facter** likewise needs a
per-host report — generate it with `nix run nixpkgs#nixos-facter -- -o facter.json`,
commit it, and point `itera.hardware.facter.reportPath` at it. Both compose with
impermanence automatically (Secure Boot keys, Flatpak apps, and libvirt VMs are
added to the persisted set when their battery is on).

**NVIDIA** is opt-in too — the drivers are unfree and hardware-specific, so they
can't be defaulted on for a hardware-agnostic image. A single switch turns on the
kernel module, `hardware.graphics`, the `nvidia` video driver, nvidia-settings,
the container toolkit, and the Wayland cursor workaround:

```nix
{ itera.nvidia.enable = true; }
```

The open kernel module is the default (`itera.nvidia.open = true`; set `false`
for the proprietary module on pre-Turing GPUs). For laptop hybrid graphics, opt
into PRIME and supply the two PCI bus IDs from `lspci` — offload is the default,
mutually exclusive with sync:

```nix
{
  itera.nvidia = {
    enable = true;
    prime = {
      enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
```

For per-machine hardware quirks, itera also re-exports
[nixos-hardware](https://github.com/NixOS/nixos-hardware) profiles (which are
import-time selections, so they aren't auto-imported) — add yours alongside the
main module:

```nix
{
  modules = [
    itera.nixosModules.default
    itera.hardwareModules.framework-13-7040-amd
  ];
}
```

## Installing from a live ISO

itera owns the disk layout through `itera.disko`, so there is no
`hardware-configuration.nix` to generate and no manual `parted`/`mkfs` step —
you install straight from your flake with disko's one-shot installer. Boot a
[NixOS live ISO](https://nixos.org/download.html), get your flake onto the
machine (clone it, or reference it as `github:youruser/yourflake`), and run, as
root:

```sh
# the live ISO usually has flakes on already; if not:
export NIX_CONFIG="experimental-features = nix-command flakes"

# partition + format per itera.disko, then install the closure
nix run 'github:nix-community/disko#disko-install' -- \
  --flake '.#myhost' \
  --disk main /dev/nvme0n1
```

Swap `.#myhost` for your `nixosConfigurations.<name>` (use
`github:youruser/yourflake#myhost` if the flake isn't local) and `/dev/nvme0n1`
for the device you set in `itera.disko.device`. **disko wipes that disk.** When
it finishes, set a root/user password if you didn't bake one in, then reboot.

Prefer the two explicit steps? Run disko yourself, then `nixos-install`:

```sh
nix run 'github:nix-community/disko' -- --mode destroy,format,mount \
  --flake '.#myhost'
nixos-install --flake '.#myhost'
```

Want to try itera on a spare machine without authoring a flake first? itera ships
a ready-to-install test host, `itera-testhost` (the bare-metal sibling of the
`itera-vm` demo), carrying the full default stack and a `tester` login. Install it
straight from GitHub — just point `--disk main` at the real target disk (it is
**wiped**); the config's placeholder device is overridden and never touched:

```sh
nix run 'github:nix-community/disko#disko-install' -- \
  --flake 'github:lcleveland/itera#itera-testhost' --disk main /dev/nvme0n1
```

Or skip picking the device by hand and use the interactive installer, which
lists the machine's disks, confirms the wipe, and runs the command above for you.
The shortest way is the remote bootstrap — nothing to clone, nothing to type
twice:

```sh
curl -fsSL https://raw.githubusercontent.com/lcleveland/itera/main/install-testhost.sh | sudo bash
```

Pass a device to skip the menu: `… | sudo bash -s -- /dev/nvme0n1`. Prefer to
invoke `nix` yourself? The bootstrap is just a shortcut for:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' \
  run 'github:lcleveland/itera#install-itera-testhost'
```

(The live ISO ships with flakes disabled and partitioning needs root, hence the
`sudo` and the experimental-features flag. The installer re-exports those into
`NIX_CONFIG` so the `nix` commands disko-install runs internally inherit them,
and reads its prompts from `/dev/tty` so the `curl | bash` pipe doesn't eat
them.)

A few itera-specific notes:

- **The root is an ephemeral tmpfs** (`itera.impermanence`, on by default), so
  anything not under a persisted path is wiped every boot. Declare what must
  survive via `itera.impermanence.directories` / `users.<name>.directories`
  _before_ installing — itera already persists logs, machine-id, SSH host keys,
  NetworkManager connections and clock state for you.
- **Set `itera.nix.stateVersion` once** to the release you installed from (the
  template uses `"25.05"`), then never change it.
- **Secure Boot is opt-in**, so a fresh install boots via systemd-boot with no
  extra steps. If you set `itera.secureBoot.enable = true`, install and boot
  first, then enroll keys and rebuild — see [Ecosystem
  integrations](#ecosystem-integrations).
- **SSH is enabled on the test systems** (password auth on, root login off) so
  you can log in to troubleshoot: `ssh tester@<lan-ip>` for a `itera-testhost`
  box, or `ssh -p 2222 dev@localhost` for the running `itera-vm` (its sshd is
  forwarded to host port 2222). This is dev-only wiring in `dev/remote-access.nix`
  and is **not** part of `nixosModules.default` — consumers get no SSH daemon.
- **Update in place with `itera-update`** instead of reinstalling per change. SSH
  in and run it: it does `nixos-rebuild switch` against the newest remote flake
  commit (`--refresh`), defaulting to this host's own attr. Test a branch with
  `ITERA_UPDATE_FLAKE=github:you/itera#itera-testhost itera-update`.

## Structure

| Path                     | Purpose                                                                                                                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `flake.nix`              | flake-parts entry point; inputs + module imports                                                                                                                                                 |
| `install-testhost.sh`    | remote bootstrap: `curl … \| sudo bash` to install `itera-testhost` from a live ISO                                                                                                              |
| `flake/`                 | flake outputs, dev shell + formatter, checks, and the `itera-vm` / `itera-testhost` configs                                                                                                      |
| `dev/`                   | dev-only host configs: `vm.nix` (QEMU demo), `test-host.nix` (on-hardware test host), `install-itera-testhost.sh` (installer), `remote-access.nix` + `update-itera.sh` (SSH in + `itera-update`) |
| `docs/`                  | reference notes (e.g. `known-boot-log-noise.md`)                                                                                                                                                 |
| `lib/`                   | helpers (module auto-import)                                                                                                                                                                     |
| `modules/nixos/`         | system layer — `itera.*` NixOS options → `nixosModules.default`                                                                                                                                  |
| `modules/nixos/core/`    | core batteries: `boot`, `nix`, `locale`, `networking`, `disko`, `impermanence`, `hardening`, `secureboot`, `secrets`, `facter`, `nix-index`, `virtualisation`                                    |
| `modules/nixos/desktop/` | desktop batteries: `mango` compositor, `dankMaterialShell` shell + greeter, `flatpak`, `file-manager` (Nemo), `browser` (ungoogled-chromium), `theme` (dark mode)                                |
| `modules/hjem/`          | home layer — per-program modules → `hjemModules.default`                                                                                                                                         |
| `overlays/`              | `pkgs.itera.*` overlay                                                                                                                                                                           |
| `pkgs/`                  | itera's own packages                                                                                                                                                                             |
| `templates/`             | downstream starter flake                                                                                                                                                                         |
| `tests/`                 | NixOS VM test harness for modules                                                                                                                                                                |

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
