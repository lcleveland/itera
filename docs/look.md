# The itera look

The spec for itera's unified visual design: colour, typography, icons, cursor, brand assets, light/dark, per-user overrides, and the contract every itera module follows. The vocabulary is in [GLOSSARY.md](../GLOSSARY.md). The reasons for each choice are in ADRs [0001](adr/0001-hand-curated-palette.md), [0002](adr/0002-three-lane-theming-contract.md), [0003](adr/0003-brand-assets-generated-from-tokens.md) and [0004](adr/0004-session-state-is-seeded-not-managed.md), and the full discussion of each decision is in the issues linked under each heading. They were charted on the [itera default look map](https://github.com/lcleveland/itera/issues/177).

Where this spec and the code disagree, the code is out of date.

## Options and the resolver

([theming contract](https://github.com/lcleveland/itera/issues/184))

- **The tree:** one `itera.look` tree with a per-user mirror at `itera.users.<name>.look`, declared with the existing `mkCuratedProgram` (no second framework). It contains:
  - `mode`, `colors.{dark,light}`, `fonts.{sans,mono,emoji,size.{sans,mono}}`, `radius`, `gaps`, `opacity`
  - `cursor.{name,package,size}` (name per mode) and `icons` (package, name per mode)
  - the auto-mode schedule and coordinates
  - the layout tokens `layout.{proportions,presets,notifications,bar.{length,perOutput}}` (see [Ultrawide](#ultrawide))
- **Merge:**
  - A per-user scalar (`nullOr`) wins when it is set.
  - Colours merge one token at a time, per mode (`sys // usr`).
  - Aliases resolve **after** the merge, so a per-user `accent` carries through to `surfaceTint` and the rest.
- **The resolver:** `iteraLib.look.resolve osConfig name` (in `lib/look.nix`) is the only code that reads `itera.look`. `resolve osConfig null` returns the system look, for surfaces that exist only system-wide (greeter, boot, console, os-release, Flatpak override). Their option docs say per-user overrides don't reach them.
- **Non-colour defaults:** `radius` and `gaps` default to DMS's own defaults in the pinned DMS source, and `opacity` is `1.0`. Nothing changes visually; the tokens exist so they can be overridden.

## Delivery lanes

([ADR 0002](adr/0002-three-lane-theming-contract.md)) Every module that themes something follows this checklist. The theming code lives in the app's own battery.

1. **DMS lane:** DMS/matugen has a template for the app. Include DMS's output, put the binary on the DMS service's PATH, and read no colours.
2. **Inherited lane:** the app follows the portal `color-scheme`, GTK/Qt, or the terminal's ANSI colours. Do nothing.
3. **Nix lane:** render from `resolve`, in both modes where the app supports it. Document that it won't follow the DMS picker or a runtime mode switch.
4. Non-colour tokens (fonts, opacity, radius, gaps) always come from `resolve`.
5. No colour literals.

**DMS disabled** ([fallback](https://github.com/lcleveland/itera/issues/191)) is supported, with reduced theming.

- **Gating:** DMS-lane wiring and its assertions are gated on `itera.desktop.dankMaterialShell.enable`, following the `dmsEnabled` pattern in `modules/programs/mango.nix`. With DMS off, DMS-lane apps keep their stock colours; they never fall through to the Nix lane.
- **Missing files:** include points must tolerate DMS's output not existing yet. Nix never seeds DMS's output files.

| Surface                 | Lane      | Delivery                                                                                                                                                       |
| ----------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DMS                     | source    | `currentThemeName = "custom"`, generated `customThemeFile` (dark + light), and `config.d` keys for fonts, `cornerRadius`, per-mode icons and `cursorSettings`. |
| GTK                     | DMS       | DMS `dank-colors.css`. adw-gtk3 is shipped and `GTK_THEME` is never set.                                                                                       |
| Qt                      | DMS       | DMS kcolorscheme/qtengine.                                                                                                                                     |
| mango                   | DMS       | Sources `dms/colors.conf`. Radius from `resolve`; gaps are seeded into DMS's spacing setting (see [Ultrawide](#ultrawide)).                                    |
| WezTerm                 | DMS       | `color_scheme = "dank-theme"`. Font, size and opacity defaults from `resolve`.                                                                                 |
| Zed                     | DMS       | DankShell Dark/Light theme (replacing One Dark/One Light). Font and size defaults from `resolve`.                                                              |
| Nushell                 | inherited | ANSI colours from the terminal.                                                                                                                                |
| Vivaldi                 | inherited | Portal `color-scheme`; fonts through fontconfig.                                                                                                               |
| mpv                     | Nix       | `osc.conf` from `resolve`.                                                                                                                                     |
| Plymouth, console       | Nix       | `resolve null` (see [Boot and console](#boot-and-console)).                                                                                                    |
| Greeter                 | Nix/DMS   | System tokens (see [Greeter](#greeter)).                                                                                                                       |
| Fonts, icons, cursor    | all       | See [Typography, icons, cursor](#typography-icons-cursor).                                                                                                     |
| Flatpaks                | inherited | See [Flatpaks](#flatpaks).                                                                                                                                     |
| systemd-boot/lanzaboote | none      | Left alone (see [Boot and console](#boot-and-console)).                                                                                                        |

The DMS theme picker stays usable, best effort. If a user picks a wallpaper or stock theme, runtime apps follow it and Nix-lane surfaces keep the itera palette ([ADR 0001](adr/0001-hand-curated-palette.md)).

## Palette: Tide

([colour source](https://github.com/lcleveland/itera/issues/183), [palette](https://github.com/lcleveland/itera/issues/188))

- **Character:** a teal accent on cool slate neutrals, with a coral tertiary. It is hand-curated in both modes, values are stored as hex, and there is no colour maths in Nix.
- **Aliases:** an arrow (→) means the token's default **refers to** another token, so overriding the source carries through.
- **Overriding:** containers and on-colours are set by hand, so the option docs tell users to override the whole accent family together.
- **Terminal block:** curated for legibility and not tinted by the accent.

| token                     | dark                              | light                             |
| ------------------------- | --------------------------------- | --------------------------------- |
| `background`              | `#0a1318`                         | `#f6fbfe`                         |
| `surface.lowest`          | `#040c12`                         | `#ffffff`                         |
| `surface.low`             | `#0f191e`                         | `#e8f6fe`                         |
| `surface.base`            | `#151e24`                         | `#e2eff7`                         |
| `surface.high`            | `#1e282e`                         | `#dbe8f1`                         |
| `surface.highest`         | `#283238`                         | `#d3e0e8`                         |
| `surfaceVariant`          | `#2a3a44`                         | `#c7dbe7`                         |
| `inverseSurface`          | `#e2e9ed` → text                  | `#141c20` → text                  |
| `text`                    | `#e2e9ed`                         | `#141c20`                         |
| `textMuted`               | `#a9b3b9`                         | `#4f5a61`                         |
| `inverseText`             | `#0a1318` → background            | `#f6fbfe` → background            |
| `accent`                  | `#4eccd3`                         | `#057176`                         |
| `accentContainer`         | `#034649`                         | `#b8e9eb`                         |
| `textOnAccent`            | `#01282a`                         | `#ffffff`                         |
| `textOnAccentContainer`   | `#c5e9eb`                         | `#023032`                         |
| `accentSecondary`         | `#96c1c3`                         | `#396669`                         |
| `accentTertiary`          | `#eba295`                         | `#944b40`                         |
| `border`                  | `#3f4950`                         | `#c0cdd5`                         |
| `borderStrong`            | `#68747b`                         | `#7c8890`                         |
| `error`                   | `#f97770`                         | `#c22826`                         |
| `warning`                 | `#f1c961`                         | `#9d6304`                         |
| `success`                 | `#86d489`                         | `#2e7c35`                         |
| `info`                    | `#79c0f1`                         | `#036eae`                         |
| `selection`               | `#034649` → accentContainer       | `#b8e9eb` → accentContainer       |
| `selectionText`           | `#c5e9eb` → textOnAccentContainer | `#023032` → textOnAccentContainer |
| `scrim`                   | `#000000`                         | `#000000`                         |
| `shadow`                  | `#000000`                         | `#000000`                         |
| `terminal.black`          | `#283238` → surface.highest       | `#141c20` → text                  |
| `terminal.red`            | `#f47b74`                         | `#ba3535`                         |
| `terminal.green`          | `#88d078`                         | `#2f751d`                         |
| `terminal.yellow`         | `#efca61`                         | `#816501`                         |
| `terminal.blue`           | `#6db0f4`                         | `#0465af`                         |
| `terminal.magenta`        | `#d98cd2`                         | `#993f94`                         |
| `terminal.cyan`           | `#65d2d2`                         | `#067272`                         |
| `terminal.white`          | `#a9b3b9` → textMuted             | `#5a656c`                         |
| `terminal.bright.black`   | `#68747b` → borderStrong          | `#4f5a61` → textMuted             |
| `terminal.bright.red`     | `#ff9b93`                         | `#a7031a`                         |
| `terminal.bright.green`   | `#a4e596`                         | `#1a6001`                         |
| `terminal.bright.yellow`  | `#ffe295`                         | `#695200`                         |
| `terminal.bright.blue`    | `#90c6fe`                         | `#01518f`                         |
| `terminal.bright.magenta` | `#eca5e5`                         | `#872082`                         |
| `terminal.bright.cyan`    | `#89e7e6`                         | `#055c5c`                         |
| `terminal.bright.white`   | `#e2e9ed` → text                  | `#343f45`                         |

**DMS mapping:**

- `primary` = `accent`, `primaryText` = `textOnAccent`, `primaryContainer` = `accentContainer`
- `secondary` = `accentSecondary`, `surfaceTint` = `accent`
- `surface*` = `surface.*`
- `surfaceText` and `backgroundText` = `text`, `surfaceVariantText` = `textMuted`
- `outline` = `border`

## Typography, icons, cursor

([typography, icons and cursor](https://github.com/lcleveland/itera/issues/185), [migration](https://github.com/lcleveland/itera/issues/202))

|           | Dark                                   | Light                         |
| --------- | -------------------------------------- | ----------------------------- |
| UI sans   | Roboto Flex (`roboto-flex`), 11pt      | same                          |
| Mono      | **itera Mono**, 12pt                   | same                          |
| Fallbacks | `noto-fonts`, `noto-fonts-color-emoji` | same                          |
| Icons     | Papirus-Dark, `teal` folders           | Papirus-Light, `teal` folders |
| Cursor    | Bibata Modern Ice, 24                  | Bibata Modern Classic, 24     |

- **itera Mono:** an itera-built derivation. Ligaturizer (fontforge) copies Fira Code's ligatures into Roboto Mono, and `nerd-font-patcher` adds the Nerd glyphs. It ships under OFL with every copyright notice kept, and it replaces the JetBrains Mono Nerd Font that `terminal.nix` installs today.
- **Fonts:** installed system-wide and set as `fonts.fontconfig.defaultFonts.{sansSerif,monospace,emoji}`. DMS `fontFamily`, `monoFontFamily` and `lockScreenFontFamily` point at the same families.
- **WezTerm and Zed:** take their font and size defaults (and WezTerm its opacity) from `resolve` in their batteries, so per-user tokens reach them. Their own `settings` keys win, as per-app escape hatches; WezTerm's `settings.font` names a family.
- **Icons:** the `iconTheme` battery stays. It installs the package from `look.icons` and sets `QS_ICON_THEME` (starting mode), dconf, and DMS `iconThemeDark`/`iconThemeLight` with `iconThemePerMode`.
- **Cursor:** one battery sends each mode's theme and size to mango (DMS `cursorSettings`), `XCURSOR_*`, dconf `cursor-theme`/`cursor-size` and `~/.Xresources`. GTK3 and XWayland apps pick up a mode change only when they relaunch.

## Light, dark and auto

([starting mode](https://github.com/lcleveland/itera/issues/199), [ADR 0004](adr/0004-session-state-is-seeded-not-managed.md))

- **Ownership:** DMS owns the live mode, and `syncModeWithPortal = true`. `look.mode` (`dark` | `light` | `auto`, default `dark`, per-user overridable) is a **seed**.
- **The seeder:** a per-user oneshot ordered before `dms.service`.
  - It **merges** the seeded keys into `~/.local/state/DankMaterialShell/session.json` (it never replaces the file) and writes the user's dconf `color-scheme`.
  - A stamp records what was seeded. It writes again only when the tokens behind it change (mode, schedule, coordinates, wallpapers), so live toggles survive logins. It lives in `modules/hjem/look-seed.nix`; other slices add their keys through the internal per-user `itera.sessionSeed` option.
- **Auto mode:**
  - It seeds `themeModeAutoEnabled = true`.
  - **Time mode (default):** dark from 18:00 and light from 06:00 (`darkFrom` and `lightFrom`), with `themeModeShareGammaSettings = false`.
  - **Location mode:** used when `latitude` and `longitude` are both set. It seeds `themeModeAutoMode = "location"`, with `nightModeUseIPLocation` off.
  - **dconf under auto:** set for the time of login, from the time schedule even in location mode; DMS corrects it once it starts.
- **DMS disabled:** `auto` falls back to dark with an eval warning.
- **System dconf floor:** `color-scheme` from the system `look.mode`, set by the `theme.nix` GTK battery, which also ships adw-gtk3.

## Brand assets

([brand identity](https://github.com/lcleveland/itera/issues/195), [mark and motif](https://github.com/lcleveland/itera/issues/198), [ADR 0003](adr/0003-brand-assets-generated-from-tokens.md))

- **Generation:** every asset is an SVG template filled with token hex values and rendered to PNG by **resvg** at build time, in both modes.
- **Reference geometry:** the `<script id="gen">` builders in `modules/nixos/desktop/brand.prototype.html` on the throwaway [`prototype/brand`](https://github.com/lcleveland/itera/tree/prototype/brand) branch (open it with `?mark=R&motif=18`).
- **Name:** the look is called **itera**. The palette is called Tide.
- **Mark ("Flow"):** in a 100×100 box, angles clockwise from 3 o'clock.
  - **Strokes:** tapered arcs on radius 35 around (50, 50), width 1.2 → 11, round ends. The teal stroke (`accent`) runs 135°→280°; the coral stroke (`accentTertiary`) runs −45°→100°.
  - **Lead-in dots:** two per stroke, in the stroke's colour, at 28° and 15° before its tail, with radii 1.4 and 2.6.
  - **The i:** stem `M50 47V64` (stroke width 8, round caps) and a dot at (50, 35), r 5, both in `text`.
- **Wordmark:** the monoline "itera" (stroke 9, round caps, all paths) in `text`, to the right of the mark at the mark's height.
- **Wallpaper motif ("Lead-in trails"):**
  - **Glows:** on `background`, a teal glow (`accent` at 0.2) up-left and a coral glow (`accentTertiary` at 0.13) down-right. Centres sit ±max(0.7H, 0.28W) horizontally and ±0.4H vertically from the mark, radius 0.9H.
  - **Trails:** 9-dot trails curve in toward the mark. Each dot grows 0.002H → 0.009H and 0.25 → 0.9 opacity, sweeping 70° while the radius closes 0.95H → 0.2H. The teal trail starts at 150° and the coral one at −30°.
  - **Mark:** centred at 0.14H.
  - **Scaling:** everything scales with height (H). Wider outputs get more spread, never a stretched image.
- **Wallpaper sizes:** each declared monitor gets a render at its exact pixel size after rotation. Otherwise the class fallback applies: 3840×2160, 5120×2160 or 5120×1440. Seeded into DMS `monitorWallpapersDark`/`Light` and `wallpaperPathDark`/`Light` (see [Ultrawide](#ultrawide)).
- **Greeter image:** 3840×2160 in both modes. The lockup (mark + wordmark, 0.09H tall) sits centred at 0.36H, inside the band that survives a 32:9 crop.
- **Where the logo appears:**
  - DMS launcher: `launcherLogoMode = "custom"`.
  - os-release: an `itera-logo` hicolor icon, with `LOGO=itera-logo` through `system.nixos.extraOSReleaseArgs`. `ID` stays `nixos`.
  - Plymouth.
- **Which tokens:** session wallpapers and the launcher logo use each user's merged tokens. The greeter image, os-release icon and Plymouth use system tokens.

## Ultrawide

([ultrawide strategy](https://github.com/lcleveland/itera/issues/187))

- **Strategy:** global defaults work at any width. Each declared monitor with a known width/height gets overrides by **aspect class**, computed from width/height after rotation: standard (< 2.0), ultrawide (2.0–2.8) or super-ultrawide (≥ 2.8). Undeclared, hot-plugged and size-less monitors get the global defaults. The merged per-user monitors drive the per-user rules.
- **Scroller proportions:** per-monitor mango `tag_rule`s (`monitor_name` regex, `id:*`, `scroller_ignore_proportion_single:0`). New column / lone window: standard 0.9/1.0, ultrawide 0.5/0.6, super-ultrawide 0.33/0.5.
- **Cycle presets:** one global set, `0.33, 0.5, 0.67, 0.9, 1.0`.
- **Bar:** one `["all"]` bar with a global length token (default `full`).
  - **Per-class bars:** an opt-in token. It makes one bar per declared output (full, full, percent 60), and undeclared outputs then get no bar.
  - **Fallback:** if any declared monitor is regex-named or size-less, itera keeps the global bar and emits an eval warning.
- **Notifications:** global, default top-center.
- **Gaps:** set as DMS's own mango gaps setting (`mangoLayoutGapsOverride`) through `config.d`. DMS keeps writing `dms/layout.conf`, and itera never sets a mango gaps line.
- **Wallpapers:** the seeder writes each declared output's variant, with the global 16:9 variant for everything else, and re-seeds only when the wallpaper token changes.
- **Lock screen:** reuses the session wallpapers.

## Greeter

([greeter and Flatpaks](https://github.com/lcleveland/itera/issues/200))

- **Source:** palette, mode and image come from **system** tokens. When the system `look.mode` is `auto`, the greeter shows dark.
- **Mirroring a user:** `itera.desktop.dankMaterialShell.greeter.syncUser` defaults to `null`. Setting it mirrors that user's whole last DMS look, which is DMS's upstream behaviour.

## Flatpaks

([greeter and Flatpaks](https://github.com/lcleveland/itera/issues/200)) Only when `itera.desktop.flatpak.enable` is on.

- **Mode:** the portal `color-scheme`, served from the seeded dconf. It switches live.
- **Fonts, icons, cursor:** installed system-wide, which nixpkgs' flatpak patch exposes in the sandbox. Theme names reach apps through gsettings.
- **The override:** one system-wide nix-flatpak `services.flatpak.overrides.global`, holding no colours. It contains:
  - read-only grants to `xdg-config/gtk-3.0` and `xdg-config/gtk-4.0`, so Flatpaks load DMS's `gtk.css`
  - `XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons`
- **GTK3 theme:** `org.gtk.Gtk3theme.adw-gtk3` and `org.gtk.Gtk3theme.adw-gtk3-dark` are added to the Flatpak packages.
- **No store grant:** there is no `/nix/store` grant, so any look file a Flatpak reads must not be a hjem symlink into the store.

## Boot and console

([boot and console](https://github.com/lcleveland/itera/issues/201)) System tokens and the Nix lane: changes show after a rebuild and reboot.

- **Plymouth:** an itera-built script theme, enabled by default by `itera.boot` (with an opt-out).
  - **Look:** the Flow mark centred on `surface`, its lead-in dots growing in sequence as the busy indicator. resvg renders one large PNG per animation step (the last is the whole mark), and the script scales them to a fifth of the screen height.
  - **Mode:** follows the system `look.mode`, and auto shows dark.
  - **Prompts:** password and message prompts in token colours, in Roboto Flex through `boot.plymouth.font`.
  - **Silent boot:** `quiet udev.log_level=3 rd.systemd.show_status=auto`, on with the splash and off with its opt-out (a `mkDefault` list would lose to any other `kernelParams`). The kernel log level stays nix-mineral's `loglevel=0`, quieter than 3.
- **systemd-boot/lanzaboote:** untouched. A UKI `.splash` is measured into PCRs 4 and 11.
- **Console:** set in `modules/nixos/core/keyboard.nix`.
  - **Colours:** `console.colors` always comes from the **dark** terminal tokens.
  - **Font:** Terminus as a `mkDefault`: `ter-v32n` if any system-declared monitor has `scale ≥ 1.5`, `ter-v20n` otherwise, and `ter-v24n` when no monitors are declared.

## Migration

([migration](https://github.com/lcleveland/itera/issues/202)) Each shim lands with the slice that removes its option and stays until the next NixOS stable release after it lands; a comment names that point.

- `itera.desktop.theme.dark` → `itera.look.mode` (`mkChangedOptionModule`, `true` → `"dark"`, `false` → `"light"`). `itera.desktop.theme.enable` stays as the GTK battery switch.
- `itera.desktop.iconTheme.package` → `itera.look.icons` package (`mkRenamedOptionModule`).
- `itera.desktop.iconTheme.name` → both per-mode icon names (`mkChangedOptionModule`).
- `itera.programs.wezterm.fontFamily` and its per-user mirror are removed (`mkRemovedOptionModule`, pointing at `look.fonts.mono`).
- The `templates/default/flake.nix` comment and the `tests/desktop-eval.nix` theme/Zed/WezTerm cases are updated with them.

## Verification

([verification](https://github.com/lcleveland/itera/issues/203)) Everything here runs in `nix flake check`; VM tests run on x86_64 only.

- **Lints:**
  - no hex colour literals outside the palette and `lib/look.nix`
  - only `lib/look.nix` reads `itera.look`
- **Assertions** (while DMS is on): `GTK_THEME` stays unset, and Zed's theme stays the DMS one.
- **Eval test:** a per-user `accent = "#c0ffee"` reaches `customThemeFile` and every Nix-lane output.
- **Contrast:** `lib/look.nix` computes WCAG 2 ratios through a 256-entry sRGB table.
  - **Thresholds:** body text 7:1; other text, on-colours, status and terminal colours (all 16 light slots on `background`) 4.5:1; accents and `borderStrong` 3:1.
  - **Shipped palette:** a failure fails the check.
  - **Overrides:** a failure is an eval warning naming the token, the pair and the ratio.
- **Brand assets:** every asset builds, at exactly the pixel size requested. There are no goldens.
- **Look VM test (`tests/nixos/look.nix`):**
  - the seeder writes Tide into `session.json` and dconf
  - re-activating keeps live edits, and a token change re-seeds
  - the Plymouth theme and `console.colors` are installed
  - the greeter uses system tokens
- **Not tested:** DMS/matugen runtime output, and screenshots.

## Out of scope

Theming apps itera doesn't ship (a consumer's own additions), beyond what the contract naturally exposes.
