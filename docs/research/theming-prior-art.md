# Prior art: unified theming in opinionated desktops

Research for [#182](https://github.com/lcleveland/itera/issues/182) (map [#177](https://github.com/lcleveland/itera/issues/177)).
Question: how do other opinionated, batteries-included desktops unify their look
across apps, and what can itera borrow or avoid? This file records facts only,
not a decision.

Sources were read on 2026-10-11 from each project's own repository or docs. Repo
paths are on the default branch as of that date.

## Omarchy (basecamp/omarchy, Arch + Hyprland)

**Theme packaging.** A theme is a directory. Bundled themes live in
`$OMARCHY_PATH/themes/<name>/` and user themes in `~/.config/omarchy/themes/`. A
theme folder (e.g. `themes/tokyo-night/`) holds `colors.toml`, `backgrounds/`,
`icons.theme`, `preview.png`, `unlock.png`/`preview-unlock.png`, `keyboard.rgb`,
`neovim.lua`, `vscode.json` and `shell.lock.toml` [O1][O2].
`colors.toml` is a flat set of named tokens: `mode`, `accent`, `selection`,
`muted`, four background steps (`background`, `dark_background`,
`darker_background`, `lighter_background`), four foreground steps, and eight
normal plus eight bright ANSI-style hues [O3].

**App opt-in.** Per-app templates live centrally in `default/themed/*.tpl`
(alacritty, btop, chromium, foot, ghostty, helix, hyprland, kitty, neovim,
obsidian, vscode and others) and use `{{ token }}` placeholders, plus helpers
such as `mix`, `hypr_gradient` and `shell_gradient` [O4][O5].
`omarchy-theme-set-templates` renders every template against the next theme's
`colors.toml`. User templates in `~/.config/omarchy/themed/` are read before the
bundled ones, and a file the theme ships itself wins over the rendered template
[O5]. So adding an app means adding one `.tpl` file, and every theme gets it for
free. The result is staged under `~/.local/state/omarchy/current/theme`.
`omarchy-theme-set` then restarts or reloads each consumer: terminal, btop,
Hyprland, and per-app `omarchy-theme-set-<app>` scripts for gnome, browser,
vscode, obsidian, keyboard RGB and others [O6].

**Security note.** Themes installed from git may not ship any `.lua`, any
terminal config or `vscode.json`. These files run code: a terminal config names
the program it launches, and a VS Code extension is arbitrary JS. The template
output is used instead. A test fails on any generated file that is neither on
the deny list nor recorded as colour-only [O6].

**Light/dark.** Each theme has one fixed mode: `mode = "light"` in
`colors.toml`, or a legacy empty `light.mode` marker. Failing both, the mode is
inferred from background luminance [O7][O1]. `omarchy-theme-set-gnome` maps that
mode onto `org.gnome.desktop.interface color-scheme`
(`prefer-light`/`prefer-dark`) and `gtk-theme` (`Adwaita`/`Adwaita-dark`). It
also sets `icon-theme` from `icons.theme`, defaulting to `Yaru-blue` [O7].
Light and dark are separate themes (e.g. `catppuccin` vs `catppuccin-latte`),
not two variants of one theme [O2].

**Branding.** About 23 bundled themes, mostly ports of community palettes plus
house themes (`matte-black`, `vantablack`, `lumon`, `hackerman`). Each ships its
own wallpapers in `backgrounds/` and an unlock image that also feeds Plymouth
(`omarchy-plymouth-set-by-theme`) [O1][O2][O6]. Community themes follow the repo
naming convention `omarchy-<name>-theme` and install from a git URL through the
menu [O1].

## COSMIC (pop-os/libcosmic, cosmic-settings)

**Theme packaging.** The theme is a typed Rust model in `libcosmic/cosmic-theme`.
A `ThemeBuilder` (palette, `accent`, `success`, `warning`, `destructive`,
`bg_color`, `neutral_tint`, `text_tint`, `spacing`, `corner_radii`, `gaps`,
`active_hint`, frosted/blur flags) derives a full `Theme`. The derived theme has
component colours for buttons, accent, success and so on, plus `is_dark` and
`is_high_contrast` [C1]. Built-in palettes are RON files (`dark.ron`,
`light.ron`) with a neutral ramp `neutral_0..10` and named accent choices
(`accent_blue`, `accent_purple` and so on) [C2]. Themes are stored as
cosmic-config entries under the IDs `com.system76.CosmicTheme.{Dark,Light}` and
`...{Dark,Light}.Builder` [C1].

**System default + per-user override.** cosmic-config searches the XDG data
dirs (`$XDG_DATA_DIRS/cosmic/<id>/v<ver>/...`, e.g. `/usr/share`) for defaults.
User writes go to `~/.config/cosmic/<id>/v<ver>/<key>` [C3]. A distro therefore
ships the branded default as data files, and users override it key by key.

**App opt-in.** Native apps get the theme by being built on libcosmic, which
reads the config and live-updates. For foreign toolkits COSMIC _exports_. It
writes `~/.config/gtk-4.0/cosmic/{dark,light}.css`, and `apply_gtk` symlinks
that into `gtk-4.0/gtk.css` and `gtk-3.0/gtk.css`. It first backs up a non-COSMIC
`gtk.css` to `gtk.css.bak` and removes only its own symlink on reset [C4]. There
are also Qt (qt5ct/qt6ct) and VS Code outputs [C5]. Export to GTK is a user
toggle in cosmic-settings, not forced.

**Light/dark.** `com.system76.CosmicTheme.Mode` holds `is_dark` (default
`true`) and `auto_switch` [C6]. Both modes always exist as separate full themes,
so a toggle swaps which one is active at runtime, with no regeneration.

**Branding.** The accent is picked from a curated palette list (or custom). The
Pop!_OS look is the default data shipped, not a separate theme mechanism [C2][C3].

## Bazzite / Universal Blue (ublue-os/bazzite, ublue-os/artwork)

**Theme packaging.** There is no theme engine. Bazzite ships upstream GNOME
and KDE with vendor defaults baked into the image under `system_files/` [B1]:

- GNOME: numbered `gschema.override` files, e.g.
  `zz0-04-bazzite-desktop-silverblue-theme.gschema.override`. It sets
  `color-scheme='prefer-dark'`, `accent-color='purple'`, Noto Sans and Fira
  Code fonts, wallpaper `convergence-dynamic.xml` for both light and dark, and
  blur-my-shell settings [B2]. Settings for extensions that ship no schema go
  in `/etc/dconf/db/distro.d/` keyfiles [B3].
- KDE: wallpapers in `/usr/share/wallpapers`, the greeter wallpaper in
  `/usr/lib/plasmalogin/defaults.conf`, panel pins via a Plasma `updates/*.js`
  script, and `kcm-about-distrorc` for About branding [B1][B4].
- Boot: a Plymouth `spinner/watermark.png` override [B1].

**App opt-in.** Apps don't opt in. Bazzite relies on toolkit defaults (Adwaita
or Breeze), the system accent and the color-scheme. Firefox gets the
third-party `firefox-gnome-theme`, kept up to date by a topgrade hook [B5].

**Light/dark.** Upstream DE behaviour, with a dark default set via gschema
override [B2].

**Branding.** Wallpapers come from a separate artwork repo,
`ublue-os/artwork/wallpapers/{bazzite,bluefin,aurora,...}` [B6]. The repo also
has a `press_kit/` with the wallpaper art [B1]. MOTD colour themes live in
`/usr/share/ublue-os/motd/themes/*.json` [B1]. Branding means wallpaper, accent,
logo and MOTD, not reskinning apps.

## Stylix (nix-community/stylix, NixOS / Home Manager)

**Theme packaging.** The palette is base16. It comes either from
`stylix.base16Scheme` (a tinted-theming scheme file) or, when that is unset,
from `stylix.image`, which runs a genetic-algorithm palette generator biased by
`stylix.polarity = "dark" | "light"` [S1]. Other shared inputs are
`stylix.fonts.{serif,sansSerif,monospace,emoji}` and `sizes`, `stylix.cursor`,
`stylix.icons` and `stylix.opacity.{desktop,applications,terminal,popups}`
[S1][S2]. A rendered palette preview lands at `/etc/stylix/palette.html` [S1].
A style guide maps base16 slots to semantic roles (e.g. default bg `base00`,
alternate bg `base01`, selection `base02`, text `base05`, error `base08`) [S3].

**App opt-in.** One module per app, `modules/<app>/{nixos,hm}.nix`, built with
`mkTarget`. A target is a list of small config functions that each declare which
inputs they need (`{ colors }`, `{ fonts }`, `{ opacity }`, `{ cfg }`). A
function is automatically dropped when its input is disabled or null [S4]. The
kitty target, for example, sets font, opacity and an `include` of a
tinted-theming template rendered from the palette [S5]. Each target gets
`stylix.targets.<name>.enable`. Targets auto-enable when the app is enabled
unless `stylix.autoEnable = false` [S1]. All of this is in-tree. There are about
99 Home Manager targets but only about 20 NixOS-level ones (chromium, console,
fontconfig, gnome, grub, gtk, kmscon, lightdm, limine, plymouth, qt, regreet and
others) [S6].

**Light/dark.** `polarity` is evaluated at build time. There is no runtime
switch in Stylix itself, so changing mode means a rebuild.

**System vs user.** Home Manager under NixOS inherits the system theme by
default (`stylix.homeManagerIntegration.autoImport`, `followSystem`). Setting a
different `stylix.image` at the HM level stops colour inheritance [S1].

**Branding.** None. Stylix is a mechanism, and users bring their own wallpaper
or scheme. `config.lib.stylix.pixel "base0A"` generates a solid wallpaper from a
palette slot [S7].

**Pitfalls the docs call out.** Disabled targets are still evaluated (`mkIf` is
descended into), so every option a loaded target mentions must exist. The
documented escape hatch is `disabledModules` [S7].

## DankMaterialShell (AvengeMedia/DankMaterialShell): itera's current shell

**Theme packaging.** There are two sources. The first is a wallpaper or seed
colour fed through matugen (Material 3 schemes, `scheme-tonal-spot` by default).
The second is a custom theme JSON with M3 role keys (`primary`, `primaryText`,
`primaryContainer`, `surface*`, `background`, `outline`, optionally `error`,
`warning`, `info`, `matugen_type`). That JSON is either dual-mode, with
top-level `dark` and `light` objects, or single-mode [D1]. You pick it with
`currentThemeName: "custom"` and `customThemeFile` in
`~/.config/DankMaterialShell/settings.json`. Themes are distributed through
registries with a `themes/<id>/theme.json` layout (`dms registry add`) [D1].

**App opt-in.** DMS bundles one matugen config and template per app in
`quickshell/matugen/{configs,templates}`: GTK3/4, Qt5ct/Qt6ct, kcolorscheme,
alacritty, foot, ghostty, kitty, wezterm, neovim, zed, firefox, niri, hyprland,
mangowc, emacs, vesktop and others [D2]. The Go core includes a template only
when the app's command or Flatpak is detected and the user hasn't listed it in
`SkipTemplates` [D3]. Output goes to a side file, never the app's main config.
For example, wezterm gets `~/.config/wezterm/colors/dank-theme.toml` and GTK
gets `~/.config/{gtk-3.0,gtk-4.0}/dank-colors.css` [D2]. **The user must
include that file**, e.g. `include dank-theme.conf` for kitty,
`theme = dankcolors` for ghostty, `@import url("dank-colors.css")` in `gtk.css`.
DMS manages only the GTK and Qt symlinks, behind toggles [D4]. Extension points
are user templates in `~/.config/matugen/config.toml` (absolute paths, under
`[config]`, gated by `RunUserTemplates`) and plugin configs in
`~/.config/matugen/dms/configs/` [D3][D4].

**Light/dark.** Generation produces both modes. Templates use `.default`
(mode-aware), `.dark` or `.light` variants, and a "Terminals – always use dark"
option swaps `.default` for `.dark` in terminal templates [D4].
`SyncModeWithPortal` couples the mode to the portal color-scheme. GTK3 follows
live via `adw-gtk3`/`adw-gtk3-dark` [D3][D4]. itera currently pins dark and
tells DMS not to follow the portal (`modules/programs/dankmaterialshell.nix`).

**Branding.** Default look is Material You from the wallpaper. Users can browse
named themes from registries.

## end-4 dots-hyprland and caelestia (matugen-style dotfiles)

**end-4 (illogical-impulse).** The wallpaper drives everything:
`quickshell/ii/scripts/colors/switchwall.sh` runs `matugen --mode <dark|light>`
over `~/.config/matugen/config.toml` with templates for GTK3/4 `gtk.css`,
Hyprland, hyprlock, fuzzel and KDE [E1][E2]. It sets GNOME `color-scheme` and
`gtk-theme` (`adw-gtk3`/`adw-gtk3-dark`) itself, and drives KDE/Qt through
`kde-material-you-colors` and the Darkly style [E2]. It can force dark terminals
regardless of mode, and it picks a `-dark`/`-light` wallpaper variant to match
the mode when one exists [E2]. Templates overwrite the apps' main config files
(e.g. `gtk-4.0/gtk.css`) rather than side files [E1].

**caelestia.** A Python CLI (`caelestia-dots/cli`) ships named schemes as
`data/schemes/<name>/<flavour>/{dark,light}.txt`. These are flat
`role hex` lines with M3 role names (`background`, `surfaceContainer` and so
on), and a dynamic scheme is derived from the wallpaper [K1]. `apply_colours`
runs each built-in app writer behind a config flag (`enableTerm`, `enableGtk`,
`enableQt`, `enableZed`, `enableBtop` ...), all defaulting to on. It renders
every file in a user templates dir, then runs an optional `postHook` with
`SCHEME_*` env vars [K2]. Running terminals are recoloured live by writing OSC
escape sequences to every `/dev/pts/*` [K2]. It writes main configs directly
(e.g. `gtk-3.0/gtk.css`, `fuzzel/fuzzel.ini`, `htop/htoprc`) [K2].

## matugen (InioX/matugen): the generator under DMS, end-4 and Noctalia-style setups

Matugen generates a Material You or base16 palette from an image or a single
colour and renders templates with a colour-aware filter engine. It also imports
custom JSON keywords [M1]. Its own Nix module runs matugen inside a
`runCommandLocal` and then `builtins.readFile`s the JSON. That is
import-from-derivation, which makes the palette available at eval time. Options
include `source_color` or `wallpaper`, `variant` (`light`/`dark`/`smart`),
`type`, `contrast`, `templates.<name>.{input_path,output_path}` and
`custom_colors` with `blend` [M2].

## Cross-cutting standard: the portal

`org.freedesktop.appearance` exposes `color-scheme` (0 = no preference,
1 = prefer dark, 2 = prefer light), `accent-color` (RGB doubles), `contrast`
and `reduced-motion` through the Settings portal [P1]. That makes it the one
runtime signal that libadwaita, Qt 6.5+, Chromium/Electron and Flatpaks can all
read. Omarchy, end-4 and Bazzite reach it indirectly by setting
`org.gnome.desktop.interface` keys [O7][E2][B2].

## Comparison

|               | Palette model                                 | Where a theme lives                                                         | App opt-in                                                                          | Light/dark                                            | Branding                                                         | System → user                      |
| ------------- | --------------------------------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------- |
| Omarchy       | Flat named tokens (`colors.toml`, ~30 keys)   | Theme dir in repo or `~/.config/omarchy/themes`                             | Central `.tpl` per app; theme file can override; reload script per app              | One mode per theme; separate light themes             | House + ported themes, each with wallpapers, unlock/Plymouth art | Single user                        |
| COSMIC        | Typed builder → derived component theme (RON) | cosmic-config: `$XDG_DATA_DIRS/cosmic` default, `~/.config/cosmic` override | Native via libcosmic; GTK/Qt/VS Code via export + symlink, user toggle              | Two full themes always present; runtime toggle + auto | Curated accent list; distro defaults as data                     | Yes, per key                       |
| Bazzite/uBlue | None (upstream DE theme)                      | gschema overrides, dconf `distro.d`, KDE defaults in image                  | None; toolkit defaults + accent                                                     | DE default, dark preset                               | Wallpapers (artwork repo), accent, Plymouth watermark, MOTD      | Vendor default, user changes in DE |
| Stylix        | base16 (scheme or from image)                 | Nix options                                                                 | In-tree `mkTarget` module per app, auto-enabled with app                            | Build-time `polarity`                                 | None                                                             | HM follows NixOS by default        |
| DMS           | Material 3 roles (matugen or custom JSON)     | `settings.json` + theme JSON / registry                                     | Bundled template per app, auto-detected, skip list; **user must include side file** | Both modes generated; portal sync optional            | Material You from wallpaper                                      | Single user                        |
| end-4         | Material 3 (matugen)                          | User dotfiles                                                               | Templates overwrite main configs                                                    | matugen `--mode`, gsettings, forced-dark terminals    | Wallpaper-driven                                                 | Single user                        |
| caelestia     | Material 3 roles (flat txt schemes)           | CLI data dir + user templates                                               | Per-app writer with `enableX` flag; user templates; `postHook`                      | dark/light files per flavour                          | Named schemes + wallpaper                                        | Single user                        |

## Patterns to borrow / pitfalls (facts observed, not a decision)

**Patterns that recur**

- **One token file, many templates.** Omarchy, Stylix, DMS, caelestia and
  matugen all keep a single palette source and render a per-app template from
  it. Adding an app means adding one template, not touching every theme
  [O4][S4][D2][K2].
- **The template carries the per-app contract.** Stylix's `mkTarget` has each
  app declare which inputs it consumes (colors, fonts, opacity) and drops parts
  automatically when an input is off [S4]. This is the closest existing
  analogue to an itera "module contract" in the Nix module system.
- **Semantic roles over raw colours.** Stylix publishes a base16 → role style
  guide [S3]. DMS, caelestia and COSMIC use named roles (surface, container,
  accent, destructive) [D1][K1][C1]. Omarchy uses graded backgrounds and
  foregrounds plus ANSI hues [O3].
- **Ship both modes as data, toggle at runtime.** COSMIC keeps two full themes
  and flips `is_dark` [C6]. DMS generates both and templates pick
  `.default`/`.dark`/`.light` [D4]. Neither needs a regenerate or rebuild to
  switch.
- **System default with per-user override at the config layer.** COSMIC
  layers `$XDG_DATA_DIRS` defaults under `~/.config` [C3]. Bazzite uses
  gschema overrides and dconf distro DBs, which users override per key
  [B2][B3]. Stylix lets HM follow NixOS by default [S1].
- **Side files plus include, not owning the main config.** DMS writes
  `dank-theme.*` beside the app config [D2]. COSMIC symlinks and backs up a
  foreign `gtk.css` [C4]. Both leave user config intact.
- **Per-target kill switch.** Examples: `stylix.targets.<x>.enable` /
  `autoEnable` [S1], DMS `SkipTemplates` [D3], caelestia `enableX` [K2].
- **A theme is more than colours.** Omarchy themes carry icons, wallpapers,
  lock and Plymouth art, and keyboard RGB [O2]. Bazzite branding is wallpaper,
  accent, Plymouth and MOTD [B1].
- **Drive the portal.** Every project that switches modes ends up setting
  `color-scheme` (directly or via gsettings) so toolkits follow [P1][O7][E2].

**Pitfalls observed**

- **Include burden.** DMS output does nothing until the user edits each app's
  config to include it [D4]. A batteries-included layer has to do that wiring
  itself.
- **Overwriting main configs.** end-4 and caelestia write `gtk.css`, `htoprc`
  and `fuzzel.ini` directly [E1][K2], which clobbers user edits. COSMIC added
  backup and ownership checks for exactly this [C4].
- **Build-time-only mode.** Stylix `polarity` and the matugen Nix module fix
  the mode at eval time [S1][M2], so a light/dark toggle means a rebuild.
- **Import-from-derivation.** The matugen Nix module reads generated JSON at
  eval time [M2]. That is IFD, which slows evaluation and is disallowed in some
  contexts (e.g. `allow-import-from-derivation = false`).
- **Evaluated-but-disabled modules.** Stylix documents that disabled targets
  still need their options to exist [S7]. A contract covering apps that may not
  be installed has to account for this.
- **Home Manager dependence.** Most Stylix targets (~99 of ~120) are HM
  modules [S6]. itera has no HM, so Stylix is a reference for structure, not
  something to drop in.
- **Themes as code.** Omarchy found that "theme" files like terminal configs,
  `.lua` and VS Code extensions execute code. It now denies them from
  git-installed themes [O6].
- **Mode inference is fragile.** Omarchy falls back to background luminance
  when no mode is declared [O7]. DMS notes that the GTK theme name must match
  polarity, or Chromium/Electron latch light [D3].
- **Per-theme wallpapers vs generated palettes.** Omarchy pairs a fixed
  palette with curated wallpapers [O2]. Matugen setups derive the palette from
  whatever wallpaper is set [E2][D1]. These are opposite answers to "which
  comes first".

## Sources

- [O1] Omarchy manual, "Making your own theme": https://learn.omacom.io/2/the-omarchy-manual/92/making-your-own-theme
- [O2] `basecamp/omarchy` `themes/`, `themes/tokyo-night/`: https://github.com/basecamp/omarchy/tree/quattro/themes
- [O3] `themes/tokyo-night/colors.toml`: https://github.com/basecamp/omarchy/blob/quattro/themes/tokyo-night/colors.toml
- [O4] `default/themed/*.tpl` (e.g. `kitty.conf.tpl`): https://github.com/basecamp/omarchy/tree/quattro/default/themed
- [O5] `bin/omarchy-theme-set-templates`: https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set-templates
- [O6] `bin/omarchy-theme-set`: https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set
- [O7] `bin/omarchy-theme-set-gnome`: https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set-gnome
- [C1] `pop-os/libcosmic` `cosmic-theme/src/model/theme.rs`: https://github.com/pop-os/libcosmic/blob/master/cosmic-theme/src/model/theme.rs
- [C2] `cosmic-theme/src/model/dark.ron`, `light.ron`: https://github.com/pop-os/libcosmic/tree/master/cosmic-theme/src/model
- [C3] `cosmic-config/src/lib.rs` (system_path via XDG data dirs): https://github.com/pop-os/libcosmic/blob/master/cosmic-config/src/lib.rs
- [C4] `cosmic-theme/src/output/gtk4_output.rs`: https://github.com/pop-os/libcosmic/blob/master/cosmic-theme/src/output/gtk4_output.rs
- [C5] `cosmic-theme/src/output/` (qt, qt56ct, vs_code): https://github.com/pop-os/libcosmic/tree/master/cosmic-theme/src/output
- [C6] `cosmic-theme/src/model/mode.rs`: https://github.com/pop-os/libcosmic/blob/master/cosmic-theme/src/model/mode.rs
- [B1] `ublue-os/bazzite` `system_files/`: https://github.com/ublue-os/bazzite/tree/main/system_files
- [B2] `zz0-04-bazzite-desktop-silverblue-theme.gschema.override`: https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/silverblue/usr/share/glib-2.0/schemas/zz0-04-bazzite-desktop-silverblue-theme.gschema.override
- [B3] `etc/dconf/db/distro.d/00-bazzite-desktop-silverblue-global`: https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/silverblue/etc/dconf/db/distro.d/00-bazzite-desktop-silverblue-global
- [B4] `usr/lib/plasmalogin/defaults.conf`: https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/kinoite/usr/lib/plasmalogin/defaults.conf
- [B5] `usr/libexec/topgrade/mozilla-gnome-theme-update`: https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/libexec/topgrade/mozilla-gnome-theme-update
- [B6] `ublue-os/artwork` `wallpapers/`: https://github.com/ublue-os/artwork/tree/main/wallpapers
- [S1] Stylix docs, Configuration: https://nix-community.github.io/stylix/configuration.html
- [S2] `stylix/opacity.nix`, `cursor.nix`, `icons.nix`, `fonts.nix`: https://github.com/nix-community/stylix/tree/master/stylix
- [S3] Stylix style guide (`doc/src/styling.md`): https://github.com/nix-community/stylix/blob/master/doc/src/styling.md
- [S4] `stylix/mk-target.nix`: https://github.com/nix-community/stylix/blob/master/stylix/mk-target.nix
- [S5] `modules/kitty/hm.nix`: https://github.com/nix-community/stylix/blob/master/modules/kitty/hm.nix
- [S6] `modules/*/{nixos,hm}.nix` tree listing: https://github.com/nix-community/stylix/tree/master/modules
- [S7] Stylix tips and tricks (`doc/src/tricks.md`): https://github.com/nix-community/stylix/blob/master/doc/src/tricks.md
- [D1] DMS docs, Custom Themes: https://danklinux.com/docs/dankmaterialshell/custom-themes
- [D2] `quickshell/matugen/configs/` and `templates/`: https://github.com/AvengeMedia/DankMaterialShell/tree/master/quickshell/matugen
- [D3] `core/internal/matugen/matugen.go`: https://github.com/AvengeMedia/DankMaterialShell/blob/master/core/internal/matugen/matugen.go
- [D4] DMS docs, Application Themes: https://danklinux.com/docs/dankmaterialshell/application-themes
- [E1] `end-4/dots-hyprland` `dots/.config/matugen/`: https://github.com/end-4/dots-hyprland/tree/main/dots/.config/matugen
- [E2] `dots/.config/quickshell/ii/scripts/colors/switchwall.sh`: https://github.com/end-4/dots-hyprland/blob/main/dots/.config/quickshell/ii/scripts/colors/switchwall.sh
- [K1] `caelestia-dots/cli` `src/caelestia/data/schemes/`: https://github.com/caelestia-dots/cli/tree/main/src/caelestia/data/schemes
- [K2] `src/caelestia/utils/theme.py`: https://github.com/caelestia-dots/cli/blob/main/src/caelestia/utils/theme.py
- [M1] `InioX/matugen` README: https://github.com/InioX/matugen
- [M2] `InioX/matugen` `module.nix`: https://github.com/InioX/matugen/blob/main/module.nix
- [P1] xdg-desktop-portal `org.freedesktop.impl.portal.Settings.xml`: https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.impl.portal.Settings.xml
