# Research: perl-less activation (etc overlay + userborn) with impermanence

Ticket: [#243](https://github.com/lcleveland/itera/issues/243)

Question: can itera turn on `system.etc.overlay.enable = true` and `services.userborn.enable = true` (the two halves of nixpkgs' `profiles/perlless.nix`) without breaking `itera.impermanence`?

Sources are read at the revs pinned in `flake.lock`:

- nixpkgs `NixOS/nixpkgs@6510408` (cited as `nixpkgs:<path>`)
- impermanence `nix-community/impermanence@7b1d382` (cited as `impermanence:<path>`)
- nix-mineral `cynicsketch/nix-mineral@108e475`
- userborn 1.0.1 (the nixpkgs package), cited as `userborn:<path>`
- shadow-utils, from the nixpkgs package's source

Test: the `itera-vm` disko VM (`nix run .#vm`) with both options added to `dev/vm.nix`, driven over ssh and a serial console. Boot, change the password with `chpasswd`, reboot inside the guest, then inspect again. The run was done on 2026-10-12.

## Verdict: no-go as-is

Turning both options on does not even evaluate. Once that is patched, the VM boots, but impermanence loses ownership and machine-id, and the second boot is unreachable over ssh. Every failure traces back to one ordering change: **userborn creates `/etc/passwd` in stage 2 (`sysinit.target`), but impermanence and itera's own activation steps run earlier, in the initrd, and assume users already exist.**

It could become a go after the itera-side changes listed under [What it would take](#what-it-would-take). That is real work in `impermanence.nix` and partly upstream in impermanence, so no implementation issue has been opened. Revisit when impermanence supports userborn natively, or if the boot/switch speedup becomes worth the work.

## What works

- **The `/etc` overlay mounts**, mutable by default, with its upper dir on the tmpfs root (`/.rw-etc`). itera already uses the systemd initrd (the 26.05 default) and a kernel newer than 6.6, so all three overlay assertions in `nixpkgs:nixos/modules/system/etc/etc-activation.nix` pass.
- **Persisted `/etc` paths still land on top of the overlay.** `/etc/NetworkManager/system-connections` (a directory bind mount) and `/etc/machine-id` (a file bind mount) appear as submounts of the overlay. The SSH host keys become symlinks into `/persist/etc/ssh` and the host key fingerprint is stable.
- **nix-mineral**'s `environment.etc` entries (modprobe blacklists, `issue`, `securetty`, `gitconfig`, `bluetooth/main.conf`) build into the overlay image without conflicts.
- **Password changes survive a reboot.** With the `users.deps` line gated (see below), itera's existing `iteraPersistShadow` copy-in / copy-out still runs before userborn: activation runs before systemd starts, and userborn in mutable mode merges the existing `/etc/shadow`. After `chpasswd itera:itera2` and a reboot, `itera2` logged in on the serial console.

## What breaks

### 1. The config does not evaluate

`modules/nixos/core/impermanence.nix` sets `system.activationScripts.users.deps = mkIf cfg.passwords.enable [ … ]`. userborn requires `system.activationScripts.users == ""` (`nixpkgs:nixos/modules/services/system/userborn.nix`). The `mkIf` sits inside `deps`, so the attrset is defined even when the condition is false, and evaluation fails with:

```
A definition for option `system.activationScripts.users' is not of type `string or (submodule)'
```

The fix is to gate the whole attrset: `users = mkIf (cfg.passwords.enable && !config.services.userborn.enable) { deps = [ … ]; }`. The test runs used this patch.

### 2. Impermanence's `chown` runs before any user exists

When a persisted directory's source doesn't exist yet, `impermanence:create-directories.bash` runs `chown "$user:$group"` by **name**, and its activation step declares `deps = [ "users" "groups" ]` (`impermanence:nixos.nix`). Under userborn both of those are empty, so the step runs in the initrd against an `/etc` with no `passwd`:

```
initrd-nixos-activation-start: chown: invalid user: ‘itera:users’
initrd-nixos-activation-start: chown: invalid user: ‘root:root’
initrd-nixos-activation-start: Error when executing mkdir "$target" at line 56!
initrd-nixos-activation-start: Error when executing ln -s "$targetFile" "$mountPoint" at line 50!
```

What you get:

- Every new persist dir is created owned by `0:0`: `/home/itera/.config` and `/home/itera/.local/state` were both root-owned.
- Ownership is only set on creation, so the wrong owner sticks on every later boot.
- `hjem-activate@itera.service` fails on both boots because it cannot write into the root-owned `~/.config`.

On a real install this hits first boot and every dir that is added to persistence later.

### 3. machine-id is never persisted, so it changes every boot

`/persist/etc/machine-id` stays `uninitialized`. itera masks `systemd-machine-id-commit` (it can't unmount under nix-mineral's `/etc` shadow mount) and instead copies the id back in the `iteraPersistMachineId` activation step. That step now runs in the initrd, before systemd has generated an id, so its "is the current id 32 hex?" guard never passes. The machine-id changed across the reboot (`7e0db3…` → `4e3daf…`). Knock-on effects seen in the VM:

- **NetworkManager gets a new DHCP lease.** The client-id derives from the machine-id, so QEMU handed out `10.0.2.16` instead of `10.0.2.15`, and the `:2222 → :22` port forward pointed at nothing. This looked like a hung reboot: sshd was running but received `0B in`. It is the failure `iteraPersistMachineId` was written to prevent.
- **`libvirtd.service` fails**, with `'/var/lib/systemd/credential.secret' comes from a different machine ID, deleting` followed by `status=243/CREDENTIALS`.

### 4. UIDs are only stable while the config doesn't change

The perl path keeps allocations in `/var/lib/nixos/uid-map`, which itera persists. userborn keeps them only in `/etc/{passwd,group}` (`userborn:README.md`: "never changes the UID of an existing user"). On a tmpfs `/etc` those files are rebuilt every boot. Allocation is deterministic, counting down from 999 in config order, so the UIDs matched across the two test boots. But adding or removing a system user without a static uid shifts the UIDs allocated after it, and files already under `/persist` (e.g. `/var/lib/dms-greeter`, owned by uid 996 in the test) would then belong to a different user. That also silently gives up userborn's protection against UID reuse.

The obvious fix doesn't work cleanly. `services.userborn.passwordFilesLocation = "/var/lib/nixos"` puts the real files on persisted storage and makes `/etc/{passwd,group,shadow}` symlinks. But shadow-utils writes with `rename(tmp, db->filename)` (`shadow:lib/commonio.c`), which replaces the symlink with a plain tmpfs file. Every `passwd` change would then be lost on reboot.

Also: `userborn-import-legacy` runs when `/var/lib/nixos/uid-map` exists and `/var/lib/userborn` doesn't. itera doesn't persist `/var/lib/userborn`, so the import re-runs on every boot. That is harmless, but it is also the only thing pinning the legacy UIDs.

## What it would take

1. **Gate `users.deps`** as shown in §1. This is a one-line fix and worth landing regardless.
2. **Run persist-dir creation after users exist.** Either chown numerically using IDs resolved from the persisted copies (see 3), or move `createPersistentStorageDirs` and the home-dir creation out of the initrd into a unit ordered `After=userborn.service`. Ideally this lands upstream in impermanence, which assumes the perl `users` script throughout.
3. **Persist `passwd`/`group`/`subuid`/`subgid` by copy**, the same way `iteraPersistShadow` already handles `shadow`: restore before userborn, save on shutdown. Also persist `/var/lib/userborn`. That restores UID stability and keeps writes from shadow-utils working.
4. **Rework machine-id persistence** to run after `systemd-machine-id-setup`, e.g. a small unit ordered after `systemd-machine-id-commit` would normally run, instead of an activation snippet.
5. **Not covered by this test:** a live `switch` that remounts `/etc`. nixpkgs' remount moves submounts across (`findmnt /etc --submounts` → `mount --bind`, then `mount --move --beneath`). nix-mineral's `/etc` shadow bind sits on top of the overlay, and after a switch it would be lazily unmounted with the old overlay. Its `nosuid,nodev` already match the overlay's options, so the expected loss is nothing, but it needs a test.

Items 2–4 are each small, but together they rework most of `impermanence.nix`'s activation glue. The payoff is a faster switch and dropping perl from activation, which isn't worth it while impermanence itself assumes the perl ordering.
