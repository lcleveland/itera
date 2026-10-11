# Hand-curated palette, not matugen

DankMaterialShell generates colours with matugen, from the wallpaper or a seed hex, and the obvious path would be to let it. itera instead declares one hand-curated palette as its own semantic colour tokens in Nix, writing both modes by hand, and hands DMS a generated custom theme file. Two reasons: the look should be recognisably itera's rather than whatever the wallpaper yields, and surfaces that only change on rebuild (Vivaldi, Nushell, mpv, boot/TTY) need the palette at build time, which wallpaper-derived colours can't give.

## Considered Options

- **Wallpaper-dynamic matugen:** no fixed brand colour, and build-time surfaces can't follow it.
- **Seeded matugen (one brand hex):** deterministic, but it gives up control over individual roles.
- **base16 / DMS keys as the token set:** a mismatch with Material 3 surfaces / no room for terminal and non-DMS roles. itera's own tokens are rendered into each of those formats instead.

## Consequences

The DMS theme picker stays usable. If a user switches to a dynamic or stock theme, runtime apps follow it and build-time surfaces keep the itera palette. This split is documented, not prevented.
