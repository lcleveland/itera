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
Dark or light. Each mode has its own hand-authored token values; dark is the default.
_Avoid_: variant, flavour

**Delivery lane**:
How a surface receives the itera look. There are three: the **DMS lane** (the surface uses DMS's generated output), the **inherited lane** (the surface follows the desktop's light/dark signal, the toolkit or the terminal's colours) and the **Nix lane** (the surface is rendered from colour tokens at build time and changes only on rebuild).
_Avoid_: target, backend

**Aspect class**:
The width family of a display, taken from its aspect ratio: standard (around 16:9), ultrawide (around 21:9) or super-ultrawide (around 32:9). Layout and wallpaper defaults vary by aspect class, not by individual display.
_Avoid_: monitor type, screen size
