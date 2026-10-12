# Research: native ultrawide support across the look

Ticket: [#186](https://github.com/lcleveland/itera/issues/186) (map [#177](https://github.com/lcleveland/itera/issues/177)).

Question: what does native ultrawide (21:9, e.g. 3440×1440; 32:9, e.g. 5120×1440) support need from each themed surface, and what hooks exist?

Sources are read at the revs pinned in `flake.lock`:

- mango `mangowm/mango@08a78c9` (cited as `mango:<path>`)
- DankMaterialShell `AvengeMedia/DankMaterialShell@60736a7` (cited as `dms:<path>`)
- matugen `InioX/matugen@main` (4.2.0) and its colour crate `material-colors 0.4.2`. itera doesn't pin matugen, so these are cited by version.

## Headline finding

**Nothing in mango or DMS matches outputs by aspect ratio or width.** Every per-monitor hook keys on the connector name (mango supports regex here, DMS needs an exact match) or on make/model/serial. So "ultrawide support" can't be expressed as a generic rule like "any 32:9 output". It has to be either:

1. generated at Nix eval time from outputs itera already knows (`itera.programs.mango.monitors` entries carry `width`/`height`, so the aspect ratio can be computed), or
2. aspect-neutral defaults that behave well at every width (fixed-pixel sizes and centring rather than proportions of the output width).

---

## 1. mango (compositor, scroller layout)

### Scroller widths and centring

Global options (`mango:docs/window-management/layouts.md`, parsed in `mango:src/config/option_defs.c`):

| Option | Default | Ultrawide relevance |
| --- | --- | --- |
| `scroller_default_proportion` | `0.9` | Width of a new column as a fraction of the output. 0.9 of 5120 px is about 4600 px, far too wide for one app. |
| `scroller_proportion_preset` | `0.5,0.8,1.0` | Widths that the cycle-width bind steps through. On 32:9 you'd want about `0.25,0.33,0.5`. **Global only.** |
| `scroller_ignore_proportion_single` | `1` | With `1`, a lone window uses its normal proportion (0.9) and is centred. |
| `scroller_default_proportion_single` | `1.0` | Width of a lone window. Takes effect only when `scroller_ignore_proportion_single=0`. |
| `scroller_structs` | `20` | Reserved side margin (px) when a column's ratio is 1. Fixed pixels, **global only**. |
| `scroller_focus_center` / `scroller_prefer_center` / `scroller_prefer_overspread` | `0`/`0`/`1` | Centring policy. Precedence is overspread > focus_center > prefer_center (layouts.md warning). **Global only.** |

**A lone window is always centred.** In `mango:src/layout/scroll.c`, `need_apply_center` is true whenever `n_heads == 1`, and the single-window branch sets `x = m->w.x + (m->w.width - width)/2`. Ultrawide therefore doesn't need a "centre the lone window" switch. It needs a **narrower single-window width** on wide outputs, for example `scroller_ignore_proportion_single=0` with `scroller_default_proportion_single=0.5` on 32:9 (about 2560 px, a 16:9-shaped area in the middle).

### Per-monitor hook: `tag_rule`

Supported `tag_rule` keys are `id`, `layout_name`, `monitor_name`, `monitor_make`, `monitor_model`, `monitor_serial`, `no_render_border`, `open_as_floating`, `no_hide`, `master_count`, `master_factor`, `scroller_default_proportion`, `scroller_default_proportion_single` and `scroller_ignore_proportion_single` (`mango:src/config/option_defs.c` around line 1126; `mango:docs/window-management/rules.md` "Tag Rules").

How matching works (`mango:src/config/reapply.c` `tag_rule_matches_monitor` / `tag_rule_apply_to_slot`, `mango:src/layout/arrange.c`):

- `monitor_name` is a **regex** against the connector name. make, model and serial must match exactly.
- **Every** matching rule is applied in file order, and a rule only overrides the fields it sets. `id:*` matches all tags. So one extra line composes with itera's existing per-tag `tag_rule=id:N,layout_name:scroller` lines (`lib/mango.nix` `mkTagLayoutLines`):

  ```ini
  tag_rule=id:*,monitor_name:^DP-1$,scroller_default_proportion:0.33,scroller_ignore_proportion_single:0,scroller_default_proportion_single:0.5
  ```

- The per-tag-per-monitor fields are layout, master count/factor and the three scroller proportions. **Presets, structs, centring policy and gaps can't be set per monitor.**
- The master-stack equivalent for ultrawide is `layout_name:center_tile` (master in the middle) together with `center_when_single_stack` (layouts.md).

### Gaps

`gap_inner_horizontal|vertical` and `gap_outer_horizontal|vertical` (`mango:docs/visuals/theming.md`) are global config. Each monitor holds its own runtime copy (`m->gappoh` etc. in `scroll.c`), and the `incgaps`/`togglegaps` dispatchers (`mango:docs/bindings/keys.md`) change it at runtime, but no config key sets gaps per output. Horizontal and vertical outer gaps are separate options, so a large `gap_outer_horizontal` (the classic way to pad an ultrawide) is possible, but only on every output at once.

Under itera, gaps are **owned by DMS**. DMS writes `mango/dms/layout.conf` with all four gap keys set from bar spacing (or `mangoLayoutGapsOverride` / `mangoLayoutGapsOutOverride`), with outer = inner by default (`dms:quickshell/Services/MangoService.qml` `generateLayoutConfig`). itera sources that file before its own options (`modules/hjem/programs/mango.nix`), so an itera-set `gap_outer_horizontal` placed after it would win, still globally.

### Monitor rules

`monitor_rule` covers name (regex), make, model, serial, width, height, refresh, x, y, scale, vrr, hdr, rr and so on (`mango:docs/configuration/monitors.md`). It has **no** layout, gap or proportion fields. itera already renders it (`lib/mango.nix` `monitorRuleType`, `renderMonitorRules`), and the greeter's mango gets the system-wide rules (`modules/nixos/desktop/dankmaterialshell.nix`).

### Window rules

`window_rule` can set `scroller_proportion` / `scroller_proportion_single` per app, plus `width`/`height`/`offset_x`/`offset_y` for floating windows (`rules.md`). Its `monitor` key **assigns** a window to an output. It does not match on one. So per-app widths can't differ by monitor.

## 2. DankMaterialShell (bar, launcher, notifications, OSD)

### Bar

`barConfigs` is a **list** of bars. Each bar has its own `screenPreferences` (`["all"]`, or connector names / models), `position`, widget sections and sizing (`dms:quickshell/Common/settings/SettingsSpec.js` `barConfigs`). The ultrawide-relevant fields are:

- `barLengthMode`: `"full"` (default), `"percent"` (with `barLengthPercent`, default 80) or `"fit"` (shrink to widgets) (`dms:quickshell/Modules/DBar/DBarBody.qml`, `Modules/Settings/DBarAppearanceTab.qml`). On 5120 px, `full` puts left and right widgets about 5000 px apart. `percent` or `fit` keep them closer to the centre.
- Per-monitor bars are possible by declaring two bar entries with disjoint `screenPreferences`, for example a `percent` bar for the ultrawide and a `full` bar for the laptop.
- itera ships one bar today with `screenPreferences = [ "all" ]` (`modules/nixos/desktop/dankmaterialshell.nix`, `settings.barConfigs`, mkDefault).

### Per-component screen filtering

`screenPreferences` is also a map keyed by component, read by `getFilteredScreens(componentId)` (`dms:quickshell/Common/SettingsData.qml`). The component ids in use are `wallpaper`, `notifications`, `osd`, `toast`, `lockScreen`, `systemTray` and `notepad`. A component's preference can choose *which* outputs it appears on, but not *where on* each output.

Matching (`dms:quickshell/Common/LayoutResolver.js` `screenMatches`) is by exact connector name, or by model when `displayNameMode == "model"`. Neither uses regex or aspect ratio.

### Launcher

The width is a fixed pixel preset (`dankLauncherV2Size`: micro/default/medium/large → `Theme.launcherWidth*`), capped at the screen width minus a margin, and centred horizontally (`dms:quickshell/Modals/DLauncherV2/DLauncherV2ModalHost.qml`, `Components/LauncherMetrics.qml`). This is **already aspect-neutral** and needs nothing per monitor.

### Notifications and OSD

- `notificationPopupPosition` takes values Top Right (default), Top Left, Top Center, Bottom Center, Bottom Right and Bottom Left (`dms:quickshell/Modules/Settings/NotificationsTab.qml`). It is global. On 32:9 a corner sits about 2500 px from the centre of gaze. `Top Center` / `Bottom Center` are the aspect-neutral choices.
- `notificationFocusedMonitor` shows popups on the focused output instead of the filtered set (`dms:quickshell/DMSShell.qml`).
- `osdPosition` (default 5, BottomCenter in the `Position` enum) and `osdPositionOverrides` are keyed by OSD *kind*, not by monitor (`SettingsData.qml`). The centred default is already fine.

All of these are `settings.json` keys, so itera can set them declaratively through its `config.d/00-itera.json` drop-in (`modules/hjem/programs/dankmaterialshell.nix`).

## 3. Wallpapers and matugen

### DMS wallpaper model

- `perMonitorWallpaper` + `monitorWallpapers` (and the `…Light`/`…Dark` variants) give each output its own image. `monitorWallpaperFillModes` gives each output its own fill mode, falling back to the global `wallpaperFillMode` (`dms:quickshell/Common/SessionData.qml` `getMonitorWallpaperFillMode`).
- Fill modes: `Stretch`, `Fit` (PreserveAspectFit), `Fill` (PreserveAspectCrop), `Tile*` and `Pad` (`dms:quickshell/Common/Theme.qml` `getFillMode`). Each output renders its own image (`dms:quickshell/Modules/WallpaperBackground.qml`). **There is no spanning mode** that stretches one image across several outputs.
- With `Fill`, a 16:9 image on a 32:9 output keeps only the middle half of its height. A 32:9 image on a 16:9 laptop keeps only the middle half of its width. The two aspect families can't share one image without heavy crop, so brand wallpapers need a variant per aspect: 16:9 (also covers 16:10 with minor crop), 21:9 and 32:9.
- **These keys live in session state (`session.json`, `SessionSpec.js` / shared session spec), not `settings.json`.** itera's settings drop-in can't set them. The runtime hook is the IPC target `wallpaper` with `set`, `setFor <screen> <path>` (which enables per-monitor mode), `getFor`, `nextFor` and `prevFor` (`dms:quickshell/Services/WallpaperCyclingService.qml`). itera's greeter sync already copies `session.json` (`modules/nixos/desktop/dankmaterialshell.nix`).

### matugen sampling

- With per-monitor wallpapers, the theme comes from **one** monitor: `matugenTargetMonitor`, or the first screen when that is empty (`dms:quickshell/Common/SessionData.qml`, `SettingsSpec.js`). It is a `settings.json` key, so it can be set declaratively.
- matugen squashes the image to a fixed **112×112** with `image::imageops::resize`, which does *not* keep the aspect ratio (`matugen:src/color/color.rs` `get_scored_colors_from_image` → `material-colors:src/image.rs`). It then quantises to 128 colours (Celebi) and scores them. Squashing keeps each region's share of the area, so **a 32:9 image is sampled over its full width, with no bias and no cropping**. The only ultrawide effect is that the seed reflects the whole wide image, including parts a 16:9 `Fill` crop would hide.
- DMS may resolve the seed colour first and pass it to matugen as `hex` (`dms:core/internal/matugen/matugen.go`). That doesn't change any aspect behaviour.

## 4. Greeter and lock screen

- **Greeter**: draws on every screen (`model: Quickshell.screens`, `dms:quickshell/Modules/Greetd/GreeterSurface.qml`). The login prompt goes on the "primary" screen, which is `Quickshell.screens[0]` (`GreeterContent.qml` `isPrimaryScreen`). There is no per-monitor option. The wallpaper comes from the synced user's per-monitor wallpaper, or `lockScreenWallpaperFillMode` / a custom path (`GreeterContent.qml` `wallpaperFillModeName`). itera's `itera.desktop.dankMaterialShell.greeter.wallpaper` is a **single path for every output**, so one image is cropped to every aspect.
- **Lock screen**: one lock surface per screen. `getFilteredScreens("lockScreen")` chooses which outputs show the prompt, and the others get `lockScreenInactiveColor` (`dms:quickshell/Modules/Lock/Lock.qml`). The background follows the per-monitor wallpaper unless `lockScreenWallpaperPath` is set. That custom path is a single image, and `lockScreenWallpaperFillMode` is a single global mode (`LockScreenBackground.qml`). The prompt and clock are centred, so they're fine at any aspect.

## 5. How other setups handle ultrawide

- **niri** gets ultrawide right as built-in behaviour: `center-focused-column "never"|"always"|"on-overflow"`, `always-center-single-column`, `preset-column-widths` with `proportion` *or* `fixed` logical-pixel widths, and `struts`. Since 25.11, layout settings can be overridden **per output** and per named workspace ([niri wiki: Configuration: Layout](https://github.com/YaLTeR/niri/wiki/Configuration:-Layout)). The ideas mango lacks are fixed-pixel column presets and per-output overrides of everything.
- **Hyprland** handles it with workspace rules that take `gapsin`/`gapsout` per workspace and bind workspaces to a monitor (`monitor:`, `m[...]` selector) ([Hyprland wiki: Workspace Rules](https://wiki.hypr.land/0.54.0/Configuring/Workspace-Rules/)). Big outer gaps on the ultrawide's workspaces are the common way to centre content.
- The common recipe is: keep a single window near 16:9 in the middle, use one-third or one-quarter column widths, put popups at top or bottom centre, and keep a wallpaper per aspect ratio.

---

## Summary table

| Surface | What ultrawide needs | Hook / option | Per-monitor? | Source |
| --- | --- | --- | --- | --- |
| mango new-column width | ~0.33 (32:9) / ~0.5 (21:9) instead of 0.9 | `scroller_default_proportion` (global) or `tag_rule …,scroller_default_proportion:` | Yes, via `tag_rule` (name regex / make / model / serial) | mango `option_defs.c`, `reapply.c`, rules.md |
| mango lone window | Narrow and centred (centring is automatic) | `scroller_ignore_proportion_single:0` + `scroller_default_proportion_single:` | Yes, via `tag_rule` | mango `scroll.c`, rules.md |
| mango width presets | Narrower cycle steps (e.g. 0.25,0.33,0.5) | `scroller_proportion_preset` | **No** (global) | layouts.md |
| mango centring policy | Prefer centring focused column | `scroller_focus_center` / `prefer_center` / `prefer_overspread` | **No** (global) | layouts.md, `scroll.c` |
| mango side margin | Optional wider struts | `scroller_structs` (px) | **No** (global) | layouts.md |
| mango master layouts | Centre master | `tag_rule …,layout_name:center_tile` | Yes, via `tag_rule` | layouts.md |
| mango gaps | Optional larger horizontal outer gap | `gap_outer_horizontal` (written by DMS `dms/layout.conf`) | **No** (global; runtime `incgaps` only) | theming.md, DMS `MangoService.qml` |
| mango per-app width | Per-app column width | `window_rule …,scroller_proportion:` | No (window rules can't match a monitor) | rules.md |
| DMS bar | Shorter bar / centred widgets | `barConfigs[].barLengthMode` = `percent`/`fit`, `barLengthPercent` | Yes: one bar entry per output via `barConfigs[].screenPreferences` | DMS `SettingsSpec.js`, `DBarBody.qml` |
| DMS launcher | Nothing (fixed px, centred) | `dankLauncherV2Size` | n/a | DMS `DLauncherV2ModalHost.qml` |
| DMS notifications | Centre position | `notificationPopupPosition` (Top/Bottom Center) | No position per monitor; `screenPreferences.notifications` picks outputs | DMS `NotificationsTab.qml`, `SettingsData.qml` |
| DMS OSD | Nothing (BottomCenter default) | `osdPosition`, `osdPositionOverrides` (per kind) | No; `screenPreferences.osd` picks outputs | DMS `SettingsSpec.js` |
| Wallpaper | Per-aspect variants (16:9 / 21:9 / 32:9); no spanning | `perMonitorWallpaper`, `monitorWallpapers`, `monitorWallpaperFillModes` (session.json); IPC `wallpaper setFor` | Yes (by connector name) | DMS `SessionData.qml`, `WallpaperCyclingService.qml` |
| matugen | Nothing (aspect-agnostic 112×112 squash) | `matugenTargetMonitor` picks which output's wallpaper seeds the theme | Picks one output | matugen `color.rs`, material-colors `image.rs`, DMS `SettingsSpec.js` |
| Greeter | Wallpaper per aspect; prompt on the intended screen | itera `greeter.wallpaper` (single path); prompt on `screens[0]` | No | DMS `GreeterContent.qml`, itera `dankmaterialshell.nix` |
| Lock screen | Wallpaper per aspect | Inherits per-monitor wallpaper; `lockScreenWallpaperPath` / `…FillMode` are single; `screenPreferences.lockScreen` | Inherited wallpaper yes; custom no | DMS `Lock.qml`, `LockScreenBackground.qml` |

## Implications for itera (facts and trade-offs, not a decision)

- **Output identity is the only key.** Both mango and DMS target outputs by connector name or model, never by aspect. itera can work out each output's aspect at eval time from `itera.programs.mango.monitors.<n>.width/height`, so "ultrawide" can be a token class (for example 16:9 / 21:9 / 32:9) that itera turns into per-monitor `tag_rule` lines and DMS `barConfigs` entries for **declared** monitors. Undeclared (hot-plugged) ultrawides get the global defaults. The choice is between global defaults that suit every width and rules that are only as good as the monitor declarations.
- **The proportion token would need two forms.** The per-monitor values (new-column and lone-window proportion) can go out per output as `tag_rule` lines that compose with itera's existing per-tag layout lines (all matching rules apply in order). The cycle presets, centring policy and struts are global, so either one compromise set is chosen for every output or the presets get tuned for the widest output.
- **Gaps are effectively DMS's.** A per-aspect gap token can't be per-monitor in mango, and DMS rewrites `dms/layout.conf` from bar spacing. An itera gap override has to come after the DMS source line (as itera's `optionsConfig` already does) and applies to every output.
- **The DMS side splits along the settings/session boundary.** Bar length, notification position, `matugenTargetMonitor` and per-component `screenPreferences` are `settings.json` keys, so itera's `config.d` drop-in can set them. Per-monitor wallpapers live in `session.json`, so they need either a session seed written on activation or the `dms ipc call wallpaper setFor` hook, and either one competes with GUI edits.
- **Multiple bars cost something.** Per-monitor bar length means replacing itera's single `[ "all" ]` bar with one entry per declared output (or per aspect class), which repeats the widget lists. A single `percent`/`fit` bar is aspect-neutral but also changes the 16:9 look.
- **Brand wallpapers need three aspect variants** (16:9, 21:9, 32:9), because there is no spanning mode and `Fill` crops heavily across aspect families. matugen samples the whole image, so the three variants should share their colour content (the same art, recomposed) or the theme seed will change when the target monitor changes.
- **The greeter and a custom lock-screen wallpaper are single-image surfaces.** Either the image is composed to survive centre-cropping at 16:9 and 32:9, or the greeter wallpaper option grows a per-output form (DMS has no per-output greeter setting, so that would mean leaning on the synced user's per-monitor session wallpapers).
- **Already fine with no work:** lone-window centring in mango, the launcher, the OSD, the lock prompt and clock, and matugen sampling.
