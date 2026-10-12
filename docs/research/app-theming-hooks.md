# Per-app theming hooks for itera's bundled surfaces

Research for [#180](https://github.com/lcleveland/itera/issues/180), part of the
"itera default look" map ([#177](https://github.com/lcleveland/itera/issues/177)).

**Question:** for each UI surface itera ships, how does it accept colours, fonts,
radius/opacity and light/dark, and can it reload at runtime or only on rebuild?

Facts only. No decision is made here. Upstream revisions checked: DankMaterialShell
`60736a7` and mango `08a78c9` (both the revs pinned in itera's `flake.lock`, 2026-10-11),
plus the `main`/`master` branches of nixpkgs, libadwaita, Zed, WezTerm, mpv,
xdg-desktop-portal-gtk and systemd on the same date.

## The cross-cutting fact: DMS already is a theme engine

Before the per-app sections: DankMaterialShell (DMS) runs matugen on every
wallpaper/theme/mode change and renders templates for many apps. Its template
registry ([`core/internal/matugen/matugen.go`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/core/internal/matugen/matugen.go))
covers several itera surfaces:

| Template ID | Gate (app detected by) | Output |
|---|---|---|
| `gtk` | always runs | `~/.config/gtk-3.0/dank-colors.css`, `~/.config/gtk-4.0/dank-colors.css` |
| `mangowc` | `mango` on PATH **and** `$MANGO_INSTANCE_SIGNATURE` set | `~/.config/mango/dms/colors.conf` (snake_case variant auto-detected) |
| `qt5ct` / `qt6ct` | `qt5ct` / `qt6ct` on PATH | `~/.config/qt{5,6}ct/colors/matugen.conf` |
| `wezterm` | `wezterm` on PATH | `~/.config/wezterm/colors/dank-theme.toml` ([config](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/matugen/configs/wezterm.toml)) |
| `zed` | `zed`/`zeditor`/`zedit` on PATH | `~/.config/zed/themes/dank-zed-theme.json` ([config](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/matugen/configs/zed.toml)) |

Each template has a `matugenTemplate<Name>` toggle in DMS settings (all default
`true`, plus a master `runDmsMatugenTemplates`, default `true`), see
[`SettingsSpec.js`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Common/settings/SettingsSpec.js).
There is no template for Vivaldi/Chromium, Nushell, mpv, Plymouth or the console. Users can add
their own matugen templates (`runUserMatugenTemplates`, default `true`;
[DMS docs](https://danklinux.com/docs/dankmaterialshell/application-themes)).

After rendering, DMS also pushes some state into the desktop
([`matugen.go`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/core/internal/matugen/matugen.go)):

- `syncColorScheme`: writes gsettings `org.gnome.desktop.interface color-scheme`
  (`prefer-dark`/`default`), **only when `syncModeWithPortal` is true**. itera sets it to
  `false` (`modules/programs/dankmaterialshell.nix`), so DMS currently never writes it.
- `syncAccentColor`: writes gsettings `accent-color` as the nearest of GNOME's nine named accents
  (CIEDE2000 distance to the matugen primary), but only when `~/.config/gtk-4.0/gtk.css`
  imports `dank-colors.css` ("Apply GTK Themes" turned on).
- `refreshGTKTheme`: flips gsettings `gtk-theme` to a built-in theme and back to `adw-gtk3[-dark]`
  so running GTK3 apps reload CSS. This is skipped if adw-gtk3 is not installed.
- `refreshGTKColorScheme`: flips `color-scheme` and back, "the only mechanism that makes running
  GTK4 apps reload ~/.config/gtk-4.0 CSS". It is opt-in (`DMS_ENABLE_GTK_REFRESH=1`) because
  Chromium can latch the wrong mode.
- `refreshQt6ct`: touches `qt6ct.conf` so qt6ct-themed apps reload.
- `signalTerminals`: sends SIGUSR1/SIGUSR2 to kitty/ghostty only. WezTerm is not signalled.

## WezTerm

itera: `modules/programs/wezterm.nix` + `modules/hjem/programs/wezterm.nix` render
`~/.config/wezterm/wezterm.lua` (`font_size`, `window_background_opacity = 0.95`,
`fontFamily` → `wezterm.font(...)`).

- **Hooks:** the Lua config. `color_scheme = "<name>"` picks a scheme, `colors = {...}` sets an
  inline palette, and `window_background_opacity`, `font`, `font_size` and the window-frame font
  are also set there. Scheme files are TOML with a `[colors]` table, searched in
  `color_scheme_dirs` plus `<config dir>/colors`. A scheme's name is `metadata.name` or, if
  absent, the file stem ([source](https://github.com/wezterm/wezterm/blob/main/config/src/config.rs)),
  so DMS's file is scheme `dank-theme`.
- **Light/dark:** `wezterm.gui.get_appearance()` returns `Light`/`Dark`/…HighContrast, read
  from the XDG Desktop Portal. "wezterm is able to detect when the appearance has changed and
  will reload the configuration when that happens" ([docs](https://wezterm.org/config/lua/wezterm.gui/get_appearance.html)).
- **Reload:** `automatically_reload_config` defaults to `true` and watches the config file
  ([docs](https://wezterm.org/config/lua/config/automatically_reload_config.html)).
  Because the hjem-written config is a store symlink, a rebuild that changes it does trigger a reload.
- **Gotchas:** DMS writes the scheme file but does not set `color_scheme` or signal WezTerm. The
  user config has to name `dank-theme`. Whether edits to a scheme file alone trigger a reload
  (as opposed to edits to `wezterm.lua`) is not confirmed. Re-evaluating the config re-reads
  the scheme dirs.

## Zed

itera: `modules/programs/zed.nix` pins `theme = { mode = dark|light; light = "One Light"; dark = "One Dark"; }`
from `itera.desktop.theme.dark`, plus `buffer_font_size`.

- **Hooks:** `settings.json` `theme` (`mode`/`light`/`dark`), `theme_overrides` (per-theme
  attribute overrides incl. `accents`), `ui_font_*` and `buffer_font_*`. Theme files are JSON in
  `~/.config/zed/themes/` ([docs](https://zed.dev/docs/themes)).
- **Light/dark:** `mode = "system"` follows the portal. gpui's Linux backend reads
  `org.freedesktop.appearance color-scheme` at start and subscribes to changes, mapping
  "no preference" → Light ([`xdg_desktop_portal.rs`](https://github.com/zed-industries/zed/blob/main/crates/gpui_linux/src/linux/xdg_desktop_portal.rs)).
  It also reads `cursor-theme`/`cursor-size` live from the portal.
- **Reload:** Zed watches the themes dir and reloads a changed theme file live (`watch_themes` in
  [`crates/zed/src/main.rs`](https://github.com/zed-industries/zed/blob/main/crates/zed/src/main.rs)).
- **Gotchas:** DMS's template writes `dank-zed-theme.json`, but itera's pinned `light`/`dark`
  names keep Zed on One Dark/Light, so the DMS theme is installed but unused. With
  `mode = "system"`, a portal answering "no preference" yields Light. That is the reason
  itera pins the mode today.

## Nushell (prompt, LS_COLORS)

itera: `modules/hjem/programs/nushell.nix` writes `config.nu` (banner, carapace,
`extraConfig`). No colours today.

- **Hooks:** `$env.config.color_config` (per-type and `shape_*` keys; values are named colours,
  `#rrggbb`, or `{fg bg attr}` records). `std/config` ships `light-theme`/`dark-theme`
  functions. `ls` uses `$env.LS_COLORS` (GNU `dircolors` syntax, e.g. from `vivid generate`).
  The prompt is whatever `PROMPT_COMMAND` renders ([book](https://www.nushell.sh/book/coloring_and_theming.html)).
- **Light/dark:** there is no native appearance detection. ANSI-indexed colours inherit the
  terminal palette, so a WezTerm scheme switch recolours them for free. `#hex` colours do not.
- **Reload:** `config.nu` is evaluated at shell start. Running shells keep their colours.
- **Gotchas:** using ANSI names rather than hex is what lets the terminal own the palette.

## Vivaldi

itera: `modules/nixos/desktop/browser.nix` (package, handlers, Ozone Wayland). No theming.

- **Hooks:** in-app themes (Background/Foreground/Highlight/Accent colours, "Get Accent Color
  From Webpage", corner rounding, transparency/blur), a theme schedule that can follow the OS
  light/dark, and "Website Appearance" Light/Dark/Auto for pages
  ([Vivaldi help](https://help.vivaldi.com/article/browser-themes/)). Themes live in the mutable
  profile under `~/.config/vivaldi`.
- **Light/dark:** Chromium's Linux `DarkModeManagerLinux` reads portal
  `org.freedesktop.appearance color-scheme` and subscribes to `SettingChanged`, falling back to
  the toolkit ([source](https://chromium.googlesource.com/chromium/src/+/main/ui/linux/dark_mode_manager_linux.cc)).
  Portal accent colour is plumbed behind a feature flag
  ([commit](https://chromium.googlesource.com/chromium/src/+/4e1c63a05bda3af72503c16fbbe5d8746b356d6d)).
- **Reload:** OS-scheduled themes and page `prefers-color-scheme` change at runtime.
- **Gotchas:** there is no documented declarative theme file or Vivaldi policy for theme colours.
  Forum reports say Vivaldi reads Chromium's `/etc/chromium/policies/managed/` (low trust,
  [forum](https://forum.vivaldi.net/topic/98415/policies-for-vivaldi)). A Linux forum thread reports
  the OS-schedule not following the system. DMS has no Vivaldi template (only Firefox/Zen/pywalfox).

## GTK3 / GTK4 / libadwaita

itera: `modules/nixos/desktop/theme.nix` sets `GTK_THEME=Adwaita:dark` (session var) and dconf
`color-scheme = prefer-dark`. Surfaces: Nemo, file-roller, virt-manager (GTK3) and
gnome-calculator (GTK4/libadwaita).

- **GTK3 hooks:** gsettings `gtk-theme` (theme name), user CSS `~/.config/gtk-3.0/gtk.css`, and
  `GTK_THEME=Name[:variant]`. The GTK docs describe `GTK_THEME` as "intended mainly for easy
  debugging of theme issues" ([GTK docs](https://docs.gtk.org/gtk4/running.html)). Plain GTK3
  has no colour-scheme concept. Dark requires a dark theme/variant, and the adw-gtk3 theme
  is the common libadwaita lookalike that DMS targets.
- **GTK4 hooks:** user CSS `$XDG_CONFIG_HOME/gtk-4.0/gtk.css` at `GTK_STYLE_PROVIDER_PRIORITY_USER`,
  the highest priority ([GTK docs](https://docs.gtk.org/gtk4/const.STYLE_PROVIDER_PRIORITY_USER.html)).
- **libadwaita hooks:** the colour scheme and accent come from `AdwSettings`. The order is debug
  env vars, then the portal, then GSettings, then legacy GtkSettings, and each later source only
  fills gaps ([`adw-settings.c`](https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/adw-settings.c)).
  Apps "follow the system accent color by default". Styling is overridable through CSS variables
  such as `--accent-bg-color` and `prefers-color-scheme` media queries
  ([libadwaita docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/styles-and-appearance.html)).
  libadwaita ignores `gtk-theme`.
- **Portal accent format:** `org.freedesktop.appearance accent-color` is an sRGB `(ddd)` tuple,
  so any colour works. `color-scheme` is `u` (0 none, 1 dark, 2 light)
  ([portal spec](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html)).
  GNOME's gsettings `accent-color` is an enum of nine names (blue, teal, green, yellow, orange,
  red, pink, purple, slate), as listed in DMS's `adwaitaAccents` table.
- **Reload:** libadwaita follows portal/gsettings `color-scheme` and accent live. GTK3 reloads
  when `gtk-theme` changes. Running GTK4 apps reload user CSS only on a colour-scheme change
  (DMS source comment, above).
- **Gotchas:**
  - `GTK_THEME` breaks libadwaita. When `GTK_THEME` is set, `AdwStyleManager` skips its whole
    stylesheet setup: it does not set `Adwaita-empty`, and it adds no libadwaita, accent or font
    CSS providers, so `prefers-color-scheme` is never applied to its stylesheet
    ([`adw-style-manager.c`](https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/adw-style-manager.c)).
    With itera's `GTK_THEME=Adwaita:dark`, gnome-calculator therefore renders with GTK4's
    built-in dark Adwaita, not libadwaita's styling, ignores the accent colour, and cannot switch
    light/dark at runtime. `GTK_THEME` is also fixed per session (an env var).
  - On mango the Settings portal backend is xdg-desktop-portal-gtk (mango's NixOS module routes
    `default = gtk`; [module](https://github.com/mangowm/mango/blob/main/nix/nixos-modules.nix)).
    Its `settings.c` exposes only `color-scheme` and `contrast` and **no `accent-color`**
    ([source](https://github.com/flatpak/xdg-desktop-portal-gtk/blob/main/src/settings.c)).
    Host libadwaita apps still get the accent from the GSettings fallback. Sandboxed (Flatpak)
    apps cannot.
  - itera's dconf `color-scheme` is a system-db default. A user-db write (DMS or the user)
    overrides it.

## Qt5 / Qt6

itera: no `qt.*` config. `icon-theme.nix` sets `QS_ICON_THEME` for Quickshell only. DMS
itself is Qt6/Quickshell and colours itself.

- **Hooks:** NixOS `qt.platformTheme` (enum including `gnome`, `kde`, `lxqt` and `qt5ct`, the
  last of which installs both qt5ct and qt6ct) sets `QT_QPA_PLATFORMTHEME`, and `qt.style`
  (`adwaita[-dark|-highcontrast…]`, `breeze`, `kvantum`, …) sets `QT_STYLE_OVERRIDE`
  ([`qt.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/qt.nix)).
  qt5ct/qt6ct read a palette from `~/.config/qt{5,6}ct/colors/*.conf` plus fonts/style in
  `qt{5,6}ct.conf`. Kvantum is an SVG-based style with its own `~/.config/Kvantum/` theme.
- **Light/dark:** since Qt 6.5, `QStyleHints::colorScheme` "follows the system's default color
  scheme" ([Qt docs](https://doc.qt.io/qt-6/qstylehints.html)). Whether that works depends on
  the active platform theme plugin.
- **Reload:** environment variables need a new session ([DMS docs](https://danklinux.com/docs/dankmaterialshell/application-themes)).
  qt6ct-themed apps pick up palette changes when `qt6ct.conf` is touched (DMS relies on this).
- **Gotchas:** DMS's qt5ct/qt6ct templates only run if the binaries are on PATH, and only take
  effect with `QT_QPA_PLATFORMTHEME=qt6ct`. `qt.platformTheme = "gnome"` asserts a style that
  supports both Qt and GTK.

## Flatpak

itera: `modules/nixos/desktop/flatpak.nix` (nix-flatpak, opt-in).

- **Hooks:** the Settings portal (colour scheme, accent, contrast) for apps that read it. GTK3
  themes are Flatpak extensions of the Freedesktop runtime (Qt themes extend the KDE runtime). Flatpak
  "can automatically detect the active Gtk theme on the host by reading the value of the
  gtk-theme DConf key" and auto-installs a matching extension. Host icons are exposed from
  `/usr/share/icons` and `$XDG_DATA_HOME/icons`, and fonts from `/usr/share/fonts` and
  `$XDG_DATA_HOME/fonts`. Host fontconfig config is not exposed
  ([Flatpak docs](https://docs.flatpak.org/en/latest/desktop-integration.html)). Per-app or
  global overrides are declarative through nix-flatpak `services.flatpak.overrides.settings`
  (`Environment`, `Context.filesystems`; [README](https://github.com/gmodena/nix-flatpak)).
- **Reload:** portal values propagate live. Overrides apply on next app launch.
- **Gotchas:** with xdg-desktop-portal-gtk, sandboxed libadwaita apps get no accent (see GTK).
  NixOS has no `/usr/share/{icons,fonts}`, so the documented host-exposure paths only cover
  user-dir assets (inference from the docs; not tested here). User `gtk.css` is invisible to the
  sandbox unless `xdg-config/gtk-4.0` is granted. The nix-flatpak README warns that overrides
  replace existing override files.

## mpv

itera: `modules/nixos/desktop/video-player.nix` (package, handlers, opt-in hwdec). No theming.

- **Hooks:** the OSC is configured through `script-opts/osc.conf` (or `--script-opts=osc-…`).
  Its colour options are `background_color`, `timecode_color`, `title_color`, `time_pos_color`,
  `time_pos_outline_color`, `buttons_color`, `top_buttons_color`,
  `small_buttons{L,R}_color` and `held_element_color`, all `#RRGGBB`. Alpha options include
  `boxalpha`, `seekrangealpha` and `floatingalpha`
  ([`osc.rst`](https://github.com/mpv-player/mpv/blob/master/DOCS/man/osc.rst)). OSD/subtitle
  options live in `mpv.conf` (`--osd-font`, `--osd-font-size`, `--sub-color`, …;
  [`options.rst`](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)).
- **Light/dark:** none.
- **Reload:** config files are read at start. The OSC registers an update callback on
  `read_options` ([`osc.lua`](https://github.com/mpv-player/mpv/blob/master/player/lua/osc.lua)),
  so `script-opts` changed at runtime (IPC/`change-list`) apply live.
- **Gotchas:** these colour options are recent. Check them against the packaged mpv version.

## gnome-calculator

itera: `modules/nixos/desktop/calculator.nix`. GTK4/libadwaita.

- **Hooks/reload:** none of its own. It is a libadwaita app (see GTK section): colour scheme and
  accent come from the portal/gsettings and switch live.
- **Gotchas:** currently defeated by `GTK_THEME` (see GTK gotchas).

## mango

itera: `modules/hjem/programs/mango.nix` writes `config.conf` and, when DMS is on,
`source_optional=./dms/{colors,layout,cursor,input,outputs,windowrules}.conf`.

- **Hooks:** `config.conf` keys such as `border_color`, `focus_color`, `urgent_color`,
  `root_color`, `drop_color`, `scratchpad_color` and `shadows_color` (format `0xRRGGBBAA`),
  plus `border_radius`, `focused_opacity`/`unfocused_opacity`, `blur*`, `shadows*` and
  `cursor_size` ([default `config.conf`](https://github.com/mangowm/mango/blob/main/assets/config.conf)).
  `source`/`source_optional` include fragments. DMS's template sets border, focus and urgent
  colours from matugen `outline`/`primary`/`error`
  ([template](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/matugen/templates/mango-colors.conf)).
- **Reload:** mango runs an inotify config watcher, debounced 150 ms
  ([`watcher.c`](https://github.com/mangowm/mango/blob/main/src/config/watcher.c), initialised
  unconditionally in `main.c`), and has a `reload_config` dispatcher.
- **Gotchas:** key names changed (`bordercolor` → `border_color`). DMS ships both
  `mangowc.toml` and `mangowc-snake.toml` and picks one by detection. The DMS template runs only
  when `$MANGO_INSTANCE_SIGNATURE` is set (inside a mango session). itera keeps DMS's `binds.conf`
  out. Ordering matters: itera's monitor rules come first (first match wins) and later scalar
  lines win.

## DMS greeter

itera: `modules/nixos/desktop/dankmaterialshell.nix` (`greeter.syncUser`, `greeter.wallpaper`).

- **Hooks:** the greeter renders from `/var/lib/dms-greeter/{settings,session,dms-colors}.json`.
  itera's greetd `preStart` wipes them, the upstream module copies the sync user's DMS files,
  and itera's settings are `jq`-merged on top (`lockScreenWallpaperPath` from `greeter.wallpaper`).
  The greeter compositor is mango with itera's monitor and xkb rules.
- **Light/dark:** whatever the synced settings and `dms-colors.json` say.
- **Reload:** only at greetd (re)start, i.e. boot or after logout. There is no live link to
  the user session.
- **Gotchas:** this is a single system-wide look, taken from one user (default: the first
  itera user with a home). Without a sync user the greeter gets only itera's system settings
  and no matugen colours.

## Plymouth

itera: not enabled.

- **Hooks:** NixOS `boot.plymouth.{enable,theme,themePackages,logo,font,extraConfig}`.
  `theme` defaults to `bgrt`. `logo` takes a PNG only (48×48 default, the NixOS snowflake).
  `font` defaults to DejaVu Sans ([`plymouth.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/plymouth.nix)).
  Themes are `.plymouth` plus script/image packages.
- **Light/dark / reload:** a static image baked into the initrd. Changes take effect after
  rebuild and reboot only.
- **Gotchas:** this is system-wide by nature, since it runs before any user exists. Per-user
  overrides are meaningless here.

## systemd-boot / lanzaboote

itera: `modules/nixos/core/boot.nix`, `core/secureboot.nix` (lanzaboote).

- **Hooks:** `loader.conf` has no colour, theme, background or font keys. Its keys are
  `default`, `timeout`, `console-mode`, `editor`, `auto-*`, `beep`, `secure-boot-enroll*`,
  `reboot*` and `log-level`, with `console-mode` setting only resolution
  ([`loader.conf.xml`](https://github.com/systemd/systemd/blob/main/man/loader.conf.xml)).
  A UKI can carry a `.splash` section ("an image (in the Windows .BMP format) to show on screen
  before invoking the kernel"), which is measured into PCRs 4+11
  ([`systemd-stub.xml`](https://github.com/systemd/systemd/blob/main/man/systemd-stub.xml)).
  lanzaboote's stub parses a `.splash` section
  ([`unified_sections.rs`](https://github.com/nix-community/lanzaboote/blob/master/rust/uefi/linux-bootloader/src/unified_sections.rs)).
  No NixOS option for supplying one was found.
- **Reload:** rebuild + reboot.
- **Gotchas:** the menu is the firmware text console. A splash changes measured-boot PCR
  values (relevant if TPM-bound secrets are pinned to PCR 11).

## Linux console (TTY) palette

itera: no colours or font set; `core/keyboard.nix` sets only `console.useXkbConfig`.

- **Hooks:** NixOS `console.colors` takes a list of 16 `RRGGBB` strings and becomes kernel params
  `vt.default_red/grn/blu`. `console.font` and `console.earlySetup` also apply
  ([`console.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/console.nix)).
- **Light/dark / reload:** fixed at boot. Kernel params change on rebuild + reboot. A running
  VT can be recoloured with escape sequences or `setvtrgb`, but nothing persists that.
- **Gotchas:** 16 colours only, system-wide, and shared with Plymouth's text fallback and the
  greeter's VT before the compositor starts.

## Summary table

| Surface | Hook | Format | Runtime reload? | Gotchas |
|---|---|---|---|---|
| WezTerm | `wezterm.lua` (`color_scheme`, `colors`, `font`, opacity); scheme TOML in `~/.config/wezterm/colors/` | Lua + TOML `[colors]` | Yes: config auto-reload; appearance change re-evaluates config | DMS writes `dank-theme.toml` but nothing selects it; no signal from DMS |
| Zed | `settings.json` `theme{mode,light,dark}`, `theme_overrides`, fonts; JSON themes in `~/.config/zed/themes/` | JSON | Yes: settings and theme dir watched; portal colour scheme live | itera pins One Dark/Light, so DMS's `dank-zed-theme.json` goes unused; `system` + no portal = Light |
| Nushell | `$env.config.color_config`, `$env.LS_COLORS`, `PROMPT_COMMAND` | Nu records / dircolors string | No: new shells only | Use ANSI names to inherit the terminal palette; no appearance detection |
| Vivaldi | In-app themes + OS schedule; Website Appearance | Mutable profile (no declarative file) | Yes for OS-scheduled light/dark via portal | No documented policy/theme file; no DMS template |
| GTK3 | gsettings `gtk-theme`, `~/.config/gtk-3.0/gtk.css`, `GTK_THEME` | Theme name / CSS | Yes on `gtk-theme` change; `GTK_THEME` per session | Dark needs a dark theme (adw-gtk3 for libadwaita look) |
| GTK4 | `~/.config/gtk-4.0/gtk.css` (USER priority) | CSS | Only on colour-scheme flip | DMS's live refresh of it is opt-in |
| libadwaita | Portal/gsettings `color-scheme`, `accent-color`; CSS vars | `u` / RGB tuple (portal), enum of 9 (gsettings) | Yes | **`GTK_THEME` disables libadwaita's stylesheet**; xdp-gtk exposes no accent |
| Qt5/6 | `QT_QPA_PLATFORMTHEME` (qt6ct…), `QT_STYLE_OVERRIDE` (kvantum…); NixOS `qt.*` | Env + INI palettes / Kvantum SVG | Palette yes (qt6ct watch); env needs new session | Nothing set in itera today; DMS template needs qt6ct on PATH |
| Flatpak | Settings portal; theme extensions; nix-flatpak overrides | D-Bus / override INI | Portal yes; overrides at launch | No accent via xdp-gtk; NixOS lacks `/usr/share` icons/fonts; host `gtk.css` hidden |
| mpv | `script-opts/osc.conf`, `mpv.conf` OSD options | `key=value`, `#RRGGBB` | OSC script-opts yes via IPC; files at start | No light/dark; options are recent |
| gnome-calculator | (libadwaita) | — | Yes (if libadwaita styling active) | Defeated by `GTK_THEME` |
| mango | `config.conf` colours/radius/opacity/blur; `source_optional` DMS fragments | `0xRRGGBBAA`, `key=value` | Yes: inotify watcher + `reload_config` | Key renames handled by DMS; template needs mango session env |
| DMS greeter | `/var/lib/dms-greeter/*.json` synced from one user + itera merge | JSON | No: at greetd start | One look system-wide |
| Plymouth | `boot.plymouth.*` | Theme pkg, PNG logo | No: rebuild + reboot | System-wide only |
| systemd-boot/lanzaboote | None in `loader.conf`; UKI `.splash` BMP | BMP | No: rebuild + reboot | Splash is measured into PCRs |
| Console | `console.colors` → `vt.default_*` | 16 × `RRGGBB` | No: reboot | 16 colours, system-wide |

## Implications for itera (facts, not decisions)

- DMS already generates matugen output for WezTerm, Zed, GTK3/4, qt5ct/qt6ct and mango from one
  palette. Whatever the look's colour source is, it either feeds DMS/matugen or competes with it.
  The remaining surfaces (Vivaldi, Nushell, mpv, Plymouth, systemd-boot, console) have no
  DMS template.
- Two itera choices currently mask DMS's output. `zed.nix` pins One Dark/Light by name, and
  nothing sets WezTerm's `color_scheme` to `dank-theme`.
- `theme.nix`'s `GTK_THEME=Adwaita:dark` disables libadwaita's stylesheet, accent and runtime
  light/dark in libadwaita apps (gnome-calculator), and is a per-session constant. dconf
  `color-scheme` alone is the hook libadwaita, Zed, WezTerm, Chromium/Vivaldi and Flatpaks read.
- Runtime light/dark is reachable for most user surfaces through one signal (portal
  `color-scheme`, backed by gsettings via xdg-desktop-portal-gtk). With `syncModeWithPortal = false`,
  DMS's mode toggle does not write that signal today.
- An arbitrary brand accent cannot reach libadwaita through gsettings, which takes one of nine
  named accents, nor through xdp-gtk, which exposes no accent. Exact accent colours for GTK4
  need CSS (`--accent-bg-color` in user `gtk.css`, which is what DMS's `dank-colors.css` route does).
- Boot-time surfaces (Plymouth, systemd-boot splash, console palette) are rebuild + reboot,
  system-wide only, and sit outside any per-user override. The greeter is system-wide too,
  sourced from one sync user.
- Every app-level hook itera already renders through hjem (WezTerm Lua, Zed JSON, Nushell
  config, mango config) is a file the existing `itera.<x>` → `itera.users.<name>.<x>` pattern
  can write. Mutable-profile apps (Vivaldi) have no such file.
