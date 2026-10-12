# Session state is seeded, not managed

Some of the look lives in state the desktop changes at runtime: DMS keeps the current mode, auto-mode schedule and per-output wallpapers in its `session.json`, and the user's dconf holds `color-scheme`. itera **seeds** that state rather than pinning it. A per-user oneshot ordered before `dms.service` merges the seeded keys into `session.json` and writes dconf. A stamp records what was seeded, so the seeder writes again only when the tokens behind it change. The user's live toggles (the DMS mode switch, a wallpaper picked in the GUI) therefore survive every login until the configuration itself changes, and then the configuration wins once.

## Considered Options

- **Pin on every login:** the configuration always wins, but any live change is lost on the next login, which fights DMS's own controls.
- **Seed on first login only:** simplest, but later configuration changes never reach existing users.
- **Seed during system activation:** no user unit, but a running DMS holds its session in memory and can write over the seed.

## Consequences

- dconf alone can't set the starting mode. With portal sync on, DMS writes `color-scheme` from its own `isLightMode` when it starts, so the seed has to go into `session.json`.
- A system-wide dconf `color-scheme` stays as a floor under every user, for users itera doesn't manage and for the moment before the seeder runs.
