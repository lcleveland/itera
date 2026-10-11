# Three delivery lanes, theming logic stays in batteries

Every itera module consumes the itera look through one `itera.look` tree, mirrored per user under `itera.users.<name>.look` with the same merge rule as `mkCuratedProgram`. A single resolver, `iteraLib.look.resolve`, merges the system and per-user values and then resolves token aliases, so a per-user `accent` override also carries through to tokens that alias it, such as `surfaceTint`. How an app gets its colours is decided per app, in this order:

1. **DMS lane:** DMS/matugen ships a template for the app, so the app includes DMS's output and reads no colours.
2. **Inherited lane:** the app follows the portal `color-scheme`, GTK/Qt, or the terminal's ANSI colours, so the module does nothing.
3. **Nix lane:** anything else renders from the resolved tokens at build time, and does not follow the DMS picker or a runtime mode switch.

Non-colour tokens (fonts, opacity, radius, gaps) always come from the resolver. DMS owns the live mode; `look.mode` only seeds it. Each lane's theming code lives in the app's own battery.

The reason is that DMS already themes and live-reloads most of the desktop, and every surface rendered in Nix is one more that the theme picker and the mode toggle can't move. itera's job is mostly to stop hiding DMS's output (Zed's One Dark pin, WezTerm never selecting `dank-theme`, `GTK_THEME`), not to re-render it.

## Considered Options

- **Every module renders tokens itself:** predictable at build time, but more surfaces stop following the picker and the mode toggle, and colour formatting spreads across batteries.
- **Look-owned targets (Stylix `mkTarget`):** strong enforcement and discoverability, but two files per app and a new abstraction. Zed, Vivaldi and the console have no include point, so this approach would need an extra exception mode on day one.
- **DMS only, no colours rendered in Nix:** least code, but console, Plymouth and mpv would visibly fall outside the look.

## Consequences

- **The DMS lane depends on DMS.** It relies on DMS internals (template ids, output paths, PATH detection) and only works while DMS is enabled. What the look does when DMS is disabled is a separate decision ([#191](https://github.com/lcleveland/itera/issues/191)).
- **Compliance is checked, not structural:**
  - a lint rejects colour literals outside the palette;
  - a lint keeps reads of `itera.look` inside `lib/look.nix`;
  - an eval test checks that a per-user accent reaches DMS's custom theme and every Nix-lane output;
  - assertions keep `GTK_THEME` and a non-DMS Zed theme out.

  The files DMS writes at runtime are covered only by a later VM test.
- **System-only surfaces ignore per-user overrides.** Console and Plymouth resolve the system look only.
