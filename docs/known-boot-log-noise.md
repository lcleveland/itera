# Known benign boot-log noise

An itera host boots to a healthy state (`systemctl is-system-running` → `running`,
`systemctl --failed` → 0 units), but the journal still carries a recurring set of
`err`/`warning` lines on every boot. They are all non-fatal. This is the triage
reference so they don't get re-investigated each time — the noise itera could fix
has been fixed; what remains is upstream or hardware-specific and is documented
here on purpose.

To pull the errors for the current boot (filtering the dbus-broker spam):

```
journalctl -b 0 -p err --no-pager | grep -v "Ignoring duplicate name"
```

## Fixed by itera

| Symptom                                                                                                                                                                                                                        | Root cause                                                                                                                                                       | Fix                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `wireplumber: failed to create directory /var/empty/.local/state/wireplumber`; `gnome-keyring-daemon: unable to create keyring dir: /var/empty/.local/share/keyrings`; `greetd: gkr-pam: unable to locate daemon control file` | The greetd `greeter` user's home is the read-only `/var/empty`, so the greeter session (wireplumber) and the greetd PAM stack (gnome-keyring) can't write state. | `modules/nixos/desktop/dankmaterialshell.nix` points the greeter at a writable tmpfs home (`/run/greeter-home` via a tmpfiles rule). |
| `systemd-oomd: No swap; memory pressure usage will be degraded`                                                                                                                                                                | itera's disko layouts ship no swap partition.                                                                                                                    | `modules/nixos/core/hardware.nix` enables `zramSwap` (compressed in-RAM swap).                                                       |
| `geoclue: Failed to connect to avahi service: Daemon not running`                                                                                                                                                              | DankMaterialShell enables `services.geoclue2` for location features; geoclue's network backend wants avahi, which was off.                                       | `modules/nixos/desktop/dankmaterialshell.nix` enables `services.avahi` (opt-out via `mkDefault`).                                    |

## Accepted — upstream (nix-mineral / nixpkgs / systemd)

See the comment block in `modules/nixos/core/hardening.nix` for the toggle points.

- **`udev-worker: Error running install command '/usr/bin/disabled-*-by-security-misc' … retcode 127`** (thunderbolt, intel_wmi_thunderbolt, pmt_class). Kicksecure's `nm-module-blacklist.conf` disables modules via a `/usr/bin/…` path absent on NixOS. It fails **closed** (the module never loads), so hardening intent is intact; only the log line is cosmetic. Toggle: `nix-mineral.settings.etc.kicksecure-module-blacklist`. Decision: accept — re-implementing natively via `boot.blacklistedKernelModules` was considered and declined.
- **`jitterentropy.service.d/overrides.conf: Failed to parse LimitMEMLOCK=`.** nixpkgs emits an empty reset line before the real `LimitMEMLOCK=2M` (which applies); systemd warns on the empty one. Report upstream rather than patch locally.
- **`systemd-sysctl: Couldn't write '0' to 'fs/binfmt_misc/status'`.** `nix-mineral.settings.kernel.binfmt-misc = false` writes the sysctl to keep binfmt_misc disabled; the write fails only because the fs isn't mounted, so the intent holds. Do **not** flip the toggle on to silence it — that weakens hardening.
- **`dbus-broker-launch: Ignoring duplicate name …` / `… is not named after the D-Bus name …`** (~120 lines/boot). An aggregation artifact of nixpkgs shipping the same `.service` files in both `/run/current-system/sw/share/dbus-1` and individual package outputs (bluez, NetworkManager, gnome-keyring, tumbler, nemo, gvfs, …), plus upstream tumbler/nemo naming quirks. Not fixable at the itera layer.

## Accepted — hardware/driver specific

These depend on the physical test machine and will not appear on other hardware:

- **`Bluetooth: hci0: Reading supported features failed (-16)`** + `bluetoothd: Failed to set default system config for hci0` — controller firmware EBUSY during early init. (Confirmed _not_ a hardening conflict: the bluetooth entries in `nm-module-blacklist.conf` are commented out and BT is active.)
- **`upowerd: value "-nan" … for property 'percentage'`** / `no valid voltage value … BAT0` — laptop battery firmware reporting quirk.
- **`wpa_supplicant: nl80211: key not allowed`** / `FT: Failed to set PTK` — Wi-Fi 802.11r fast-transition driver quirk.
