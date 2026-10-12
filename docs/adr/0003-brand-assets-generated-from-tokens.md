# Brand assets are generated from tokens

Most distros ship curated photos (COSMIC, elementary, Omarchy) or commissioned art (Fedora). itera instead generates every brand asset (logo, wallpapers, greeter image) from SVG templates filled with colour tokens and rendered to PNG with resvg at build time. Three reasons. Every aspect class and every declared monitor's exact size can be rendered rather than cropped. Both modes come for free. And a per-user accent override carries through to that user's wallpapers and launcher logo, which no fixed file can do.

## Considered Options

- **Curated photos or art:** richer visuals, but they never match the palette exactly, put binaries in git and can't follow token overrides.
- **Handmade artwork:** the most distinctive, but it needs an artist, four or more files per mode, and it is frozen against token changes.
- **Shipping the SVG directly:** DMS accepts SVG wallpapers, but its oksvg rasteriser covers only a subset of SVG for colour extraction, and the greeter's handling of SVG is untested.

## Consequences

The look is limited to what can be drawn as vector shapes in a template; photographic wallpapers are out. Templates hold no `<text>`, because the build sandbox has no fonts, so the wordmark is stored as paths.
