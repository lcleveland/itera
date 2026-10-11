# DankMaterialShell theming surface

Research for [#179](https://github.com/lcleveland/itera/issues/179) (map [#177](https://github.com/lcleveland/itera/issues/177)).

**Question:** What theming does DankMaterialShell (DMS) expose, and can it be the hub or a consumer of itera's look?

**Reference versions (from `flake.lock`):**

| Input | Rev | Short link prefix used below |
|---|---|---|
| `dms` (AvengeMedia/DankMaterialShell) | `60736a73814fd0b861316972d2c1924f8e6f8b4e` | `DMS:` = `https://github.com/AvengeMedia/DankMaterialShell/blob/60736a73814fd0b861316972d2c1924f8e6f8b4e/` |
| `dank-qml-common_2` (DMS's `DCommon` submodule) | `bd90e4b6f2ec36035fc2cb560acdc0e418f669ac` | `DQC:` = `https://github.com/AvengeMedia/dank-qml-common/blob/bd90e4b6f2ec36035fc2cb560acdc0e418f669ac/` |
| `dank-greeter` | `a91ca2ad486bfc25bd23f624c542d695c2dfb8b8` | `DG:` = `https://github.com/AvengeMedia/dank-greeter/blob/a91ca2ad486bfc25bd23f624c542d695c2dfb8b8/` |

The source was read from the Nix store (`nix flake prefetch github:AvengeMedia/DankMaterialShell/<rev>`). The local `matugen` is 4.2.0. Secondary sources: the DMS docs at danklinux.com (custom themes, application themes) and the matugen wiki. Where a doc and the code disagree, this note follows the code.

---

## 1. Two colour sources: fixed themes and matugen dynamic colours

`currentThemeName` (default `"purple"`, `DQC:DCommon/Common/settings/SharedSettingsSpec.js` L82) picks the colour source:

| `currentThemeName` | Source | Where it's defined |
|---|---|---|
| `blue`, `purple`, `green`, `orange`, `red`, `cyan`, `pink`, `amber`, `coral`, `monochrome` | **Stock themes.** Hard-coded dark and light palettes. | `DMS:quickshell/Common/StockThemes.js` |
| `custom` | **Custom theme file.** A JSON file at `customThemeFile`. | `DMS:quickshell/Common/Theme.qml` (`loadCustomTheme`, `resolveCustomTheme`, `customThemeFileView`) |
| `dynamic` | **Matugen.** Colours come from the wallpaper (`kind=image`), or from `matugenSeedColor` / `materialWallpaperSeed` (`kind=hex`). | `Theme.qml` `_executeThemeGeneration` |

The `dynamic` source has these knobs, all in `DMS:quickshell/Common/settings/SettingsSpec.js` L29–63:
- `matugenScheme` (default `scheme-tonal-spot`)
- `matugenSmartMode`
- `matugenSourceMode` (default `dominant`)
- `matugenContrast`
- `matugenSeedColor`
- `matugenSpec` (`2021` default, `2025`, or `dms`; see `DMS:core/internal/matugen/spec.go`)
- `matugenTargetMonitor`
- `generateThemeAtStartup`

**App templates run with every colour source, not only `dynamic`.** For stock and custom themes, `_executeThemeGeneration` builds a dark/light colour map and calls `setDesiredTheme(..., stockColors)`. That runs `dms matugen queue ... --stock-colors <json>` (`Theme.qml` ~L1760–1830). In Go, `buildOnce` handles that flag by logging "Using stock/custom theme colors with matugen base" and running `matugen color hex <primaryDark>` with the stock palette passed through `--import-json-string` (`DMS:core/internal/matugen/matugen.go` L428–450). As a result, GTK, terminals, mango and the other apps follow a fixed palette exactly as they follow a wallpaper.

### Custom theme file format

The format is documented at <https://danklinux.com/docs/dankmaterialshell/custom-themes> and confirmed in `resolveCustomTheme`:
- **Shape:** either a flat colour object, or `{ "dark": {...}, "light": {...} }`.
- **Variants:** an optional `variants` block, either `options` or `multi` with `flavors` × `accents`. The chosen variant is stored in `registryThemeVariants`.
- **Keys:** camelCase colour names, the same set the stock themes use: `primary`, `primaryText`, `primaryContainer`, `secondary`, `surfaceTint`, `surface`, `surfaceText`, `surfaceVariant`, `surfaceVariantText`, `surfaceContainer{Lowest,Low,,High,Highest}`, `background`, `backgroundText`, `outline`.
- **Optional keys:** `error`, `warning`, `info`, and `matugen_type`.

The docs note that some keys DMS itself never renders are still needed because they're "exported to matugen templates". The file is watched (`watchChanges: currentTheme === "custom"`), so edits apply live.

### Can DMS take a fixed palette from Nix? Yes.

itera already writes DMS settings through `~/.config/DankMaterialShell/config.d/00-itera.json` (`modules/hjem/programs/dankmaterialshell.nix`). The loader is at `DMS:quickshell/Common/SettingsData.qml` L3965. Setting these two keys there makes DMS and every detected app template render a Nix-provided palette:

```json
{ "currentThemeName": "custom", "customThemeFile": "/nix/store/…-itera-theme.json" }
```

A dynamic-but-seeded option also exists: `currentThemeName = "dynamic"` with a `matugenSeedColor`. This generates a full M3 scheme from a single hex colour.

---

## 2. Matugen templates DMS ships and runs

The template registry is `templateRegistry` in `DMS:core/internal/matugen/matugen.go` L62–86. Each template's TOML is in `DMS:quickshell/matugen/configs/`, and its source file is in `DMS:quickshell/matugen/templates/`. All output paths are relative to `$XDG_CONFIG_HOME` unless marked otherwise.

| ID | Detected by | Output(s) |
|---|---|---|
| `dank` (always) | — | `~/.cache/DankMaterialShell/dms-colors.json` (the shell's own palette) |
| `gtk` | **always runs** | `gtk-3.0/dank-colors.css`, `gtk-4.0/dank-colors.css` (a separate light variant is used for gtk3 in light mode) |
| `kcolorscheme` | **always runs** | `~/.local/share/color-schemes/DankMatugen{,Light,Dark}.colors` |
| `niri` | `niri` | `niri/dms/colors.kdl` |
| `hyprland` | `Hyprland` | `hypr/dms/colors.lua` |
| `mangowc` | `mango` + `$MANGO_INSTANCE_SIGNATURE` | `mango/dms/colors.conf` (legacy or snake_case dialect; post-hook `mmsg dispatch reload_config`) |
| `qt5ct` / `qt6ct` | `qt5ct` / `qt6ct` | `qt5ct/colors/matugen.conf`, `qt6ct/colors/matugen.conf` |
| `qtengine` | `QT_QPA_PLATFORMTHEME=qtengine` | `qtengine/config.json` (points at the kcolorscheme output) |
| `fcitx5` | `fcitx5` or config dir | `~/.local/share/fcitx5/themes/dms/{theme.conf,panel.svg,highlight.svg}` |
| `firefox` | `firefox` | `DankMaterialShell/firefox.css` (userChrome) |
| `pywalfox` | `pywalfox` | `~/.cache/wal/dank-pywalfox.json`, `~/.cache/wal/colors.json` |
| `zenbrowser` | `zen*` / Flatpak | `DankMaterialShell/zen.css` |
| `vesktop` / `vencord` / `equibop` | command, Flatpak or config dir | `<app>/themes/dank-discord.css` (Flatpak-aware) |
| `ghostty` | `ghostty` | `ghostty/themes/dankcolors` |
| `kitty` | `kitty` | `kitty/dank-theme.conf`, `kitty/dank-tabs.conf` |
| `foot` | `foot` | `foot/dank-colors.ini` |
| `alacritty` | `alacritty` | `alacritty/dank-theme.toml` |
| `wezterm` | `wezterm` | `wezterm/colors/dank-theme.toml` |
| `nvim` | `nvim` | `nvim/colors/dms.lua`, `nvim/lua/lualine/themes/dms.lua` |
| `dgop` | `dgop` | `dgop/colors.json` |
| `vscode` | per-editor extension dir | DMS theme extension files (vscode, codium, cursor, windsurf, insiders) |
| `emacs` | `emacs` + Emacs config dir | `<emacs>/themes/dank-emacs-theme.el` |
| `zed` | `zed` / `zeditor` / `zedit` | `zed/themes/dank-zed-theme.json` (themes "DankShell Dark/Light[ Transparent]") |

**Mechanics:**
- **Detection.** A template is added to the merged matugen config only when its app's command is on DMS's `PATH`, or its Flatpak or config dir exists (`appendConfigContent`, `appExists`, `configDirExists`). `gtk` and `kcolorscheme` run unconditionally.
- **Per-template toggles.** Each template has a `matugenTemplate<Name>` setting (default `true`), and `runDmsMatugenTemplates` (default `true`) is a master switch (`SettingsSpec.js` L1137–1230). The shell turns these into `--skip-templates` (`Theme.qml` ~L1820).
- **Terminal colours.** Terminals get 16 ANSI colours from DMS's `dank16` generator (`generateDank16Variants`). `terminalsAlwaysDark` forces dark terminal colours.
- **Post-render refresh.** After rendering, DMS refreshes running apps (`matugen.go` L543–577):
  - GTK: sets the `accent-color` gsetting to the nearest Adwaita accent, round-trips `gtk-theme` and `color-scheme`. This only happens if `~/.config/gtk-4.0/gtk.css` references `dank-colors.css`.
  - KDE: runs `plasma-apply-colorscheme`, only if `kdeglobals` already uses a DankMatugen scheme.
  - Also: qt6ct refresh, qtengine sync, terminal signals, fcitx5 reload.
- **Applying to toolkits.** "Apply GTK/Qt colours" are explicit actions that run `quickshell/scripts/gtk.sh` and `quickshell/scripts/qt.sh`. `gtk.sh apply` copies adw-gtk3 into `~/.local/share/themes` and patches it, or falls back to an `@import` of `dank-colors.css` in `gtk.css` (see the danklinux application-themes docs).
- **Disable switch.** `DMS_DISABLE_MATUGEN=1` turns all generation off (`Theme.qml` L25).

### How users add their own templates

There are three extension points, all merged into one matugen config per run (`buildMergedConfig`, `matugen.go` L673–770):

1. **`~/.config/matugen/config.toml`.** Its `[config]` section is merged in, and its `[templates]` section is appended, when `runUserMatugenTemplates` is on (default `true`).
2. **`~/.config/matugen/dms/configs/*.toml`.** Every `.toml` file here is appended unconditionally. This is a drop-in dir, so Nix/hjem can write template fragments here without owning the user's matugen config. It appears only in the code; the docs don't mention it.
3. **`~/.config/matugen/palette-inject.json`.** This runs external commands that emit JSON palettes and merges each one under its own namespace, so templates can reference e.g. `{{mypalette.color0}}` (`DMS:core/internal/matugen/paletteinject.go`).

Template syntax is plain matugen: `[templates.<name>]` with `input_path` and `output_path`, plus an optional `post_hook` (DMS's own configs use it). [Custom colours](https://github.com/InioX/matugen/wiki/Configuration) go under `[config.custom_colors]`. The DMS docs say user template paths must be absolute.

---

## 3. Light/dark handling

- **Where the state lives.** `isLightMode` is **session state**, not a setting: `DQC:DCommon/Common/settings/SharedSessionSpec.js` L5 (default `false`), persisted in `~/.local/state/DankMaterialShell/session.json`. **The `config.d` drop-in only layers over settings.json**, so itera can't pin `isLightMode` through it today. It relies on the default `false`.
- **Switching mode.** `Theme.setLightMode` saves the session, writes COSMIC's `is_dark`, and regenerates every template in the new mode (`Theme.qml` L1436). Turning on matugen smart mode also disables manual switching.
- **DMS → system (outbound).** With `syncModeWithPortal` (default `true`), each matugen run sets the `org.gnome.desktop.interface color-scheme` gsetting to `prefer-dark` or `default` (`syncColorScheme`, `matugen.go` ~L1515). `PortalService.setSystemColorScheme` does the same from QML.
- **System → DMS (inbound).** `PortalService.handlePortalColorScheme` follows genuine portal `color-scheme` transitions after a 750 ms debounce. This is skipped when `syncModeWithPortal` is off, when automatic theme mode (`themeModeAutoEnabled`, time or location based) is on, or when dynamic smart mode is on (`DMS:quickshell/Services/PortalService.qml` L95–145).
- **What itera sets today.** itera sets `syncModeWithPortal = false` (`modules/programs/dankmaterialshell.nix`), so neither direction syncs. Separately, `modules/nixos/desktop/theme.nix` sets `GTK_THEME=Adwaita:dark` and a dconf `color-scheme`. `GTK_THEME` overrides the `gtk-theme` gsetting, which is the key DMS round-trips to refresh GTK and which its adw-gtk3 path relies on.
- **Light/dark per surface.**
  - Icon themes can differ per mode (`iconThemeDark`, `iconThemeLight`, `iconThemePerMode`).
  - Custom and stock themes carry separate dark and light palettes.
  - Wallpapers can differ per mode (`wallpaperPathLight`, `wallpaperPathDark` in session.json).

## 4. Radius, fonts, icons, cursor

All of these are plain settings keys, so they're all settable from itera's `config.d` drop-in. Except where noted, the defaults are in `DQC:.../SharedSettingsSpec.js`.

| Concern | Keys (default) | Effect outside the shell |
|---|---|---|
| Radius | `radiusStrength` (50), `radiusMode` (`scale`), `fixedRadius` (12). The derived value is `SettingsData.cornerRadius`. | Written as compositor `border_radius` (mango `layout.conf`). Per-compositor overrides: `mangoLayoutRadiusOverride`, `niri…`, `hyprland…`. |
| Gaps and borders | `mangoLayoutGapsOverride`, `mangoLayoutGapsOutOverride`, `mangoLayoutBorderSize` | mango `layout.conf` |
| Fonts | `fontFamily` ("Google Sans Flex"), `monoFontFamily` ("Fira Code"), `displayFontFamily`, `fontWeight` (400), `fontScale` (1.0) | Shell UI only. No template exports fonts to apps. |
| Icons | `iconThemeDark`, `iconThemeLight` ("System Default"), `iconThemePerMode` | Writes `gtk-icon-theme-name` into `gtk-{3,4}.0/settings.ini` (skipped if read-only). Sets the icon theme through the DMS freedesktop settings portal and in COSMIC's config. Passed to qtengine. (`SettingsData.qml` ~L1550–1610) |
| Cursor | `cursorSettings = { theme ("System Default"), size (24), niri/hyprland/dwl/mango sub-objects }` (`SettingsSpec.js` L935) | mango `cursor.conf` (`cursor_size`, `cursor_theme`, `cursor_hide_timeout`). Also reads and updates Xresources `Xcursor.*`. |
| Surfaces and transparency | `popupTransparency`, `widgetColorMode`, `hostSurfaceColor`, `cardSurfaceColor`, … | Shell UI only |

Fonts aren't part of the matugen data at all. DMS doesn't propagate fonts to GTK, Qt or terminals.

## 5. Mango fragments DMS writes

`MangoService.qml` (`DMS:quickshell/Services/MangoService.qml` L25–32) owns `~/.config/mango/dms/`. That dir holds `binds.conf`, `outputs.conf`, `layout.conf`, `cursor.conf`, `input.conf` and `windowrules.conf`. The matugen `mangowc` template adds `colors.conf`, whose content is:

```
bordercolor = 0x{{colors.outline…}}ff
focuscolor  = 0x{{colors.primary…}}ff
urgentcolor = 0x{{colors.error…}}ff
```

`layout.conf` contains `border_radius`, the border width, and gaps (legacy `gappih…` or snake_case `gap_inner_*`). `dms config` detects the dialect (`core/internal/mangoconf`). itera's mango battery sources `dms/{colors,layout,cursor,…}.conf` with `source_optional`, placed so itera's own monitor, XKB and layout lines win (`modules/hjem/programs/mango.nix` ~L158–171). The colours template only runs inside a live mango session (`RequiredEnv: MANGO_INSTANCE_SIGNATURE`).

## 6. Greeter theme sync

The greeter is the separate `dank-greeter` flake. `programs.dms-greeter.configHome` expands to `configFiles` (`DG:distro/nix/greeter.nix` L255–258):

- `<home>/.config/DankMaterialShell/settings.json`
- `<home>/.local/state/DankMaterialShell/session.json`
- `<home>/.cache/DankMaterialShell/dms-colors.json`

greetd's `preStart` copies these files into the greeter cache (`/var/lib/dms-greeter`), along with:
- the wallpapers named in session.json (`wallpaperPath`, `wallpaperPathLight`, `wallpaperPathDark`, and the per-monitor variants), rewriting their paths;
- the file at `customThemeFile`, saved as `custom-theme.json`, with the path rewritten;
- the file at `lockScreenWallpaperPath`.

It then renames `dms-colors.json` to `colors.json` (`DG:distro/nix/greeter.nix` ~L200–253). The greeter's `Theme.qml` reads `$DMS_GREET_CFG_DIR` or `/var/cache/dms-greeter` + `/colors.json` (`DMS:quickshell/Common/Theme.qml` L2392–2414). The greeter never runs matugen (`generateSystemThemesFromCurrentTheme` returns early in greeter mode). It only renders what the synced user last generated.

**How itera's greetd wiring interacts with this.** itera's own `preStart` (`modules/nixos/desktop/dankmaterialshell.nix`) first clears the cache. After the upstream copy, it jq-merges itera's `config.d` keys over the synced settings.json. That merge runs *after* the upstream `customThemeFile` copy step. So if `customThemeFile` is set only by itera, the greeter gets the original path, not a copied one. A `/nix/store` path is world-readable, so the greeter can still read it. With `syncUser = null`, the greeter gets no `dms-colors.json` and only itera's system-wide keys.

---

## Implications for itera

These are facts and trade-offs for the decision tickets. No decision is made here.

**DMS as the hub (DMS generates, apps consume).**
- *For:*
  - DMS already renders one palette into GTK, KDE/Qt, WezTerm, Zed, mango, Firefox and others, and refreshes running apps when the mode or palette changes.
  - A Nix-written `customThemeFile`, or a `matugenSeedColor`, makes that palette deterministic.
  - Users can add templates through the `~/.config/matugen/dms/configs/` drop-in, which hjem can write into without touching the user's own matugen config.
- *Against:*
  - Output is runtime state (files in `$XDG_CONFIG_HOME`, `~/.cache` and gsettings). It isn't available at build time or before first login, and it isn't present on systems without DMS.
  - Templates run only for apps detected on DMS's `PATH`.
  - No template covers Vivaldi, Nushell, mpv, Plymouth or the TTY.
  - Fonts aren't covered at all.

**DMS as a consumer (Nix owns the tokens, DMS is one more target).**
- *For:*
  - Every key DMS needs is a settings key itera already writes through `config.d`: `currentThemeName = "custom"` plus `customThemeFile`, radius, fonts, icon themes and cursor.
  - The same token set could render a custom-theme JSON for DMS and also native config for apps DMS doesn't cover.
- *Against:*
  - DMS would still run its own templates over the Nix palette unless itera turns them off (`runDmsMatugenTemplates`, the per-template toggles, or `DMS_DISABLE_MATUGEN`). Otherwise two writers target overlapping files: GTK css, WezTerm and Zed theme files, and mango colours.

**Hybrid.** Nix supplies the palette (custom theme JSON) and DMS's template engine distributes it. In this mode DMS is "consumer of tokens, hub for propagation".

**Known frictions to resolve whichever way is chosen:**
- **Light/dark has three writers today.** itera's `theme.nix` (`GTK_THEME` env and dconf), DMS's `isLightMode` (session.json, not reachable through `config.d`), and DMS's portal sync (off in itera).
  - `GTK_THEME=Adwaita:dark` pins GTK3's theme. That conflicts with DMS's adw-gtk3 patching and its `gtk-theme` refresh.
- **Zed.** itera's Zed module pins `theme.mode` from `itera.desktop.theme.dark`, and doesn't name the DMS-generated "DankShell Dark/Light" theme.
- **WezTerm.** DMS writes `wezterm/colors/dank-theme.toml`. WezTerm uses it only if its config sets that colour scheme.
- **Per-user overrides.** These map cleanly, because every theming key except `isLightMode` and the wallpapers lives in settings, which itera already merges as system default plus per-user override.
- **Greeter.** The greeter mirrors one user's theme (`syncUser`), or none. It can't follow a per-user look at login time, because it renders only the last-generated `dms-colors.json` of one user.
- **Brand assets.** Stock theme names are fixed, so a branded itera palette would be a custom theme file. Its required key set is the camelCase list in §1.
