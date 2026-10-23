# itera

A hjem-based NixOS layer that ships an opinionated desktop with a consistent look out of the box.

## Look

**itera look**:
The unified visual design every itera-shipped surface follows: colours, typography, icons, cursor and brand assets.
_Avoid_: theme, rice, skin

**Colour token**:
A named semantic colour role in the itera look (such as `accent` or `surface.high`), defined once per mode. Surfaces consume colours only through these tokens.
_Avoid_: colour variable, swatch

**Palette**:
The complete set of colour token values for both modes. itera ships exactly one, hand-curated.
_Avoid_: colour scheme, theme

**Mode**:
Dark or light. Each mode has its own hand-authored token values; dark is the default. Auto mode is not a third mode.
_Avoid_: variant, flavour

**Delivery lane**:
How a surface receives the itera look. There are three: the **DMS lane** (the surface uses DMS's generated output), the **inherited lane** (the surface follows the desktop's light/dark signal, the toolkit or the terminal's colours) and the **Nix lane** (the surface is rendered from colour tokens at build time and changes only on rebuild).
_Avoid_: target, backend

**Aspect class**:
The width family of a display, taken from its aspect ratio: standard (around 16:9), ultrawide (around 21:9) or super-ultrawide (around 32:9). Layout and wallpaper defaults vary by aspect class, not by individual display.
_Avoid_: monitor type, screen size

**Brand asset**:
The itera logo, wallpapers or greeter image. Each is generated from colour tokens for each mode, not drawn or sourced as a fixed file.
_Avoid_: artwork, branding

**Auto mode**:
The look switching between dark and light on its own, by time of day or by the sun at the user's location.
_Avoid_: system mode, adaptive theme

**Seed**:
A starting value itera writes into state the user can change live, such as the current mode or a display's wallpaper. A seed is written again only when the setting behind it changes, so the user's own changes survive in between.
_Avoid_: default, pin

## Programs

**Curated program**:
An app whose user-facing settings itera declares once, settable both as a system default and as a per-user override.
_Avoid_: managed app, wrapped program

**System default**:
The value a curated program's setting takes for every user who doesn't override it.
_Avoid_: global setting, base config

**Per-user override**:
One user's own value for a curated program's setting. It wins over the system default, and an override left unset inherits the system default. Some settings, such as keybinds, combine with the system default entry by entry instead of replacing it.
_Avoid_: user config, user setting

**Plain user**:
A user declared without an itera user entry. A plain user has no per-user overrides, so every setting is its system default. A setting that has no system level takes its default.
_Avoid_: non-itera user, unmanaged user

**Resolved settings**:
One user's effective settings for a curated program: the system defaults with that user's per-user overrides applied.
_Avoid_: merged config, effective config
