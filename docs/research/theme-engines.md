# Theme engines for a hjem-based NixOS layer

Research for [#178](https://github.com/lcleveland/itera/issues/178), part of the
"itera default look" map ([#177](https://github.com/lcleveland/itera/issues/177)).
It sets out facts and trade-offs only. The choice belongs to a separate HITL ticket.

**Question:** which theme engine could drive itera's look, and how well does each
fit a NixOS layer with no home-manager (user files written by hjem)? Candidates:
Stylix, matugen (on its own and through DMS), tinted-theming/base16 (nix-colors and
similar), and a hand-rolled token module.

Sources were checked on 2026-10-11 against upstream `master`/`main` and the nixpkgs
revision in itera's `flake.lock` (nixos-unstable, release 26.11).

## Where itera starts from

- `modules/nixos/desktop/theme.nix` sets `GTK_THEME=Adwaita:dark` and the dconf
  `color-scheme`, and that is all of it. `icon-theme.nix` installs Adwaita and
  sets `QS_ICON_THEME`.
- DMS is imported through its upstream NixOS module. `enableDynamicTheming`
  defaults to `true`, and that option is what puts `pkgs.matugen` on the system
  ([distro/nix/common.nix](https://github.com/AvengeMedia/DankMaterialShell/blob/master/distro/nix/common.nix),
  [distro/nix/options.nix](https://github.com/AvengeMedia/DankMaterialShell/blob/master/distro/nix/options.nix)).
  **matugen therefore already ships with itera.**
- itera pins `syncModeWithPortal = false`, so DMS stays dark. The greeter
  sync already copies `dms-colors.json` (`modules/nixos/desktop/dankmaterialshell.nix`).
- Per-app fonts and opacity are set directly in `modules/programs/{wezterm,zed}.nix`.
  Zed follows `itera.desktop.theme.dark` by hand because it reads neither GTK nor dconf.

## 1. Stylix

Repo: [nix-community/stylix](https://github.com/nix-community/stylix). MIT licence,
about 2.4k stars, commits within the last few days. It has no GitHub releases and
uses release branches that follow NixOS. A warning fires when the Stylix and NixOS
releases differ ([stylix/nixos/default.nix](https://github.com/nix-community/stylix/blob/master/stylix/nixos/default.nix)).

- **Without home-manager:** this is the weak point. The installation docs say:
  _"Many applications cannot be configured system wide, so Stylix will also need
  Home Manager … You can theoretically use it without installing Home Manager,
  however most features will be unavailable."_
  ([doc/src/installation.md](https://github.com/nix-community/stylix/blob/master/doc/src/installation.md)).
  The per-app targets bear this out. Going by the `modules/*/{nixos,hm}.nix`
  files in the repo tree:
  - **NixOS targets** (no HM needed): chromium, console (TTY), feh, fish,
    fontconfig, font-packages, glance, gnome, gnome-text-editor, grub, gtk,
    gtksourceview, kmscon, lightdm, limine, neovim, plymouth, qt, regreet,
    spicetify.
  - **HM-only targets** that cover itera's apps: **wezterm, zed, nushell, mpv,
    dank-material-shell**, and the real GTK theming too. The NixOS `gtk` target
    only sets `programs.dconf.enable = true` "Required for Home Manager's GTK
    settings to work"
    ([modules/gtk/nixos.nix](https://github.com/nix-community/stylix/blob/master/modules/gtk/nixos.nix)).
  - There is no mango target, and no hjem integration exists upstream or anywhere
    else that a search turned up. The only bridge is
    `home-manager-integration.nix`, which copies NixOS `stylix.*` into HM
    ([stylix/home-manager-integration.nix](https://github.com/nix-community/stylix/blob/master/stylix/home-manager-integration.nix)).
    Issue [#390](https://github.com/nix-community/stylix/issues/390) (docs for use
    without HM) is still open.
- **What remains usable without HM:** the NixOS module still computes the palette
  and exposes it as `config.lib.stylix.colors` (a base16.nix scheme attrset,
  [stylix/palette.nix](https://github.com/nix-community/stylix/blob/master/stylix/palette.nix)).
  It also exposes fonts, cursor and opacity options. itera could read these from
  its own hjem renderers, which makes Stylix little more than a palette source
  with option names attached.
- **Per-user overrides:** only through HM (each user's HM `stylix.*` takes the
  NixOS value with `mkDefault`). Without HM there are no per-user Stylix options.
- **Palette source:** static base16 scheme (`base16Scheme`) or generated at build
  time from `stylix.image` by its own genetic-algorithm generator (a
  `runCommand`, so it is reproducible but costs a rebuild).
- **Light/dark:** one `polarity` per evaluation (`either|light|dark`). Runtime
  toggling is open issue [#447](https://github.com/nix-community/stylix/issues/447).
  The usual workaround is NixOS specialisations, which have their own open bugs
  ([#504](https://github.com/nix-community/stylix/issues/504),
  [#540](https://github.com/nix-community/stylix/issues/540)). Its DMS target
  writes the same palette into both the `dark` and `light` slots
  ([modules/dank-material-shell/hm.nix](https://github.com/nix-community/stylix/blob/master/modules/dank-material-shell/hm.nix)).
- **Generation:** at build time, fully reproducible.

## 2. matugen

Repo: [InioX/matugen](https://github.com/InioX/matugen). **GPL-2.0** ([LICENSE](https://github.com/InioX/matugen/blob/main/LICENSE)),
about 2.1k stars, latest release v4.2.0 (2026-08-17). It is in nixpkgs as
`matugen` 4.2.0 (`GPL-2.0-or-later`). It is a Rust tool that generates Material
You (M3) or base16 palettes from an **image or a single hex colour**, with light,
dark and contrast variants, and has its own template engine
([README](https://github.com/InioX/matugen#readme)).

### 2a. matugen on its own

- **Without home-manager:** yes. The flake exports `nixosModules.matugen`
  ([flake.nix](https://github.com/InioX/matugen/blob/main/flake.nix)). The module
  ([module.nix](https://github.com/InioX/matugen/blob/main/module.nix)) runs matugen
  inside `pkgs.runCommandLocal` at **build time** from `source_color` or
  `wallpaper`, and exposes `programs.matugen.theme.files` (rendered templates) and
  `theme.colors` (JSON). Those are plain store paths, which hjem can link
  anywhere. The CLI can also run at runtime.
- **Per-user overrides:** not built in. itera would have to evaluate the module
  (or call the CLI derivation) once per user.
- **Palette source:** a static seed colour or a wallpaper. Each run produces a
  `dark` or `light` variant (`variant` option). Light and dark need two runs or
  both template modes.
- **App coverage:** none until templates are written. The community repo
  [InioX/matugen-themes](https://github.com/InioX/matugen-themes/tree/main/templates)
  has templates for wezterm, zed, vivaldi, gtk, qtct, mango, quickshell, kitty,
  foot, alacritty, ghostty, and more. It has none for nushell, mpv or Nemo
  specifically (Nemo is covered by the GTK template).

### 2b. matugen through DankMaterialShell (what itera already runs)

DMS: [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell),
MIT, about 8.4k stars, pushed today.

- **Theme modes** ([quickshell/Common/Theme.qml](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Common/Theme.qml)):
  stock themes (`currentThemeName = "blue"`…), `dynamic` (from the wallpaper), and
  `custom` (a JSON `customThemeFile` with separate `dark` and `light` objects).
  It switches between light and dark **at runtime** through `isLightMode`, or
  follows the portal (`syncModeWithPortal`).
- **Templates run for every mode, not just dynamic.** For stock or custom themes
  the Go backend feeds the theme's primary, surface and container colours into
  matugen ("Using stock/custom theme colors with matugen base",
  [core/internal/matugen/matugen.go](https://github.com/AvengeMedia/DankMaterialShell/blob/master/core/internal/matugen/matugen.go)).
  `matugenSeedColor` and `matugenScheme` are settings as well
  ([SettingsSpec.js](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Common/settings/SettingsSpec.js)).
- **Bundled templates** ([quickshell/matugen/configs](https://github.com/AvengeMedia/DankMaterialShell/tree/master/quickshell/matugen/configs)),
  each with its own `matugenTemplate<App>` toggle, all on by default:
  gtk3/gtk4 (`~/.config/gtk-{3,4}.0/dank-colors.css`), qt5ct/qt6ct, kcolorscheme,
  **mangowc** (`~/.config/mango/dms/colors.conf`, followed by `mmsg reload_config`),
  **wezterm** (`~/.config/wezterm/colors/dank-theme.toml`), **zed**
  (`~/.config/zed/themes/dank-zed-theme.json`), ghostty, kitty, foot, alacritty,
  neovim, vscode, emacs, firefox/pywalfox, zen, vesktop/vencord/equibop, fcitx5,
  niri, hyprland. A template runs only when its app's command is on `PATH`
  (mango also needs `MANGO_INSTANCE_SIGNATURE`). `runUserMatugenTemplates`
  adds the user's own templates.
- **Without home-manager:** yes. DMS writes these files itself, at runtime, into
  `$XDG_CONFIG_HOME`. The app configs that itera generates through hjem would have
  to _reference_ them: WezTerm `color_scheme = "dank-theme"`, Zed theme name,
  GTK `@import 'dank-colors.css'`. That part is still to be wired up.
- **Per-user:** comes for free. DMS state lives per user, and itera already merges
  `itera.programs.dankMaterialShell.settings` with per-user overrides into
  `config.d/00-itera.json`.
- **Not covered:** nushell, mpv, Vivaldi (DMS has no template; matugen-themes has
  `vivaldi.css`), boot/TTY, and anything rendered before login apart from the DMS
  greeter (which itera already syncs).
- **Reproducibility:** generated at runtime, so the files are mutable state outside
  the Nix store. The output depends on the wallpaper or theme picked in the GUI,
  and on the DMS and matugen versions. It cannot be checked at build time.

## 3. tinted-theming / base16 (nix-colors and similar)

- **Spec and schemes:** [tinted-theming/home](https://github.com/tinted-theming/home)
  (MIT) maintains the base16 and base24 specs (plus "Tinted8", per the tinty README).
  [tinted-theming/schemes](https://github.com/tinted-theming/schemes) (MIT, active)
  holds 361 base16 and 210 base24 schemes. The old `base16-schemes` repo is
  archived. nixpkgs ships them as `base16-schemes` (0-unstable-2026-01-15).
- **Nix libraries:**
  - [Misterio77/nix-colors](https://github.com/Misterio77/nix-colors): **archived**
    (read-only, last push 2024-05). GPL-3.0. Should not be used.
  - [SenchoPens/base16.nix](https://github.com/SenchoPens/base16.nix): MIT, last
    push 2025-08. A small library (`mkSchemeAttrs`, template rendering) that
    Stylix builds on. It works in any module system, hjem included.
- **App templates:** separate repos under the org, each in Mustache. Most of the
  per-terminal repos (tinted-kitty, tinted-foot, tinted-alacritty…) are archived
  and merged into [tinted-terminal](https://github.com/tinted-theming/tinted-terminal),
  which covers **wezterm**, ghostty, kitty, foot and others. Other active repos
  include **tinted-zed**, base16-gtk-flatcolor, tinted-shell, tinted-vim,
  tinted-tmux and tinted-vscode. None exists for nushell, mpv, Vivaldi, mango or
  DMS.
- **Runtime manager:** [tinted-theming/tinty](https://github.com/tinted-theming/tinty)
  (GPL-3.0, in nixpkgs 0.34.1). It clones template repos into
  `~/.local/share/tinted-theming/tinty` at runtime, which goes against Nix
  reproducibility.
- **Without home-manager:** yes, if base16.nix (or a plain YAML-to-attrset import)
  is paired with hjem-written files. Per-user overrides are whatever itera builds.
- **Palette source:** static, picked from a library. There is no wallpaper
  extraction (tinted-scheme-extractor-rs exists but is outside the Nix path). Light
  and dark are two separate schemes. base16 has 16 slots, so it carries no
  surface/container/elevation roles of the M3 kind that DMS uses. Stylix's DMS
  target shows the squeeze: it maps 16 slots onto about 20 M3 roles.

## 4. Hand-rolled itera token module

itera would own a set of options such as
`itera.look.{palette.{dark,light}, fonts, cursor, icons, radius, opacity}`, with
`itera.users.<name>.look.*` overrides following the existing pattern. Each itera
module would render the tokens through hjem.

- **Without home-manager:** native, since hjem and NixOS are all that is involved.
- **Per-user:** exactly the `itera.<x>` → `itera.users.<name>.<x>` contract itera
  already uses.
- **Palette source:** anything. Hand-picked hex values, a base16 YAML from
  `pkgs.base16-schemes`, or a build-time **matugen** run from a brand seed colour
  (`matugen color hex …` inside a derivation, as matugen's own NixOS module does).
  The last option gives M3 roles for both modes, reproducibly.
- **App coverage:** zero until each renderer exists, but itera ships about 12 apps,
  not 100. matugen-themes, DMS and tinted templates can be copied as starting
  points if licences allow (matugen-themes and DMS are separate projects; check
  each template's licence before vendoring).
- **Light/dark:** both palettes can be built ahead of time. Switching at runtime
  still needs a mechanism, for example DMS `isLightMode` and the portal, or
  per-app dual themes (Zed `theme.light`/`theme.dark`, a WezTerm Lua
  `get_appearance()` check). That belongs to the map's "light/dark propagation"
  ticket.
- **Maintenance and licence:** itera owns all of it, under itera's licence. No
  upstream churn, but every new module must follow the contract (the
  token-coverage check in the map's "verification" item).

## Comparison

|                                   | Stylix                                                                                             | matugen (standalone)                                              | matugen via DMS                                                                                   | tinted/base16 (+base16.nix)                                       | Hand-rolled tokens                         |
| --------------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------ |
| Works without HM                  | Partly: palette, fonts, console, plymouth, grub/limine, qt, chromium; **itera's apps are HM-only** | Yes (`nixosModules.matugen`, store paths)                         | Yes (DMS writes `~/.config` itself)                                                               | Yes (library + hjem)                                              | Yes, native                                |
| Per-user overrides                | Only via HM                                                                                        | Build it yourself                                                 | Yes (per-user DMS settings, already merged by itera)                                              | Build it yourself                                                 | Yes, existing `itera.users.<name>` pattern |
| Palette source                    | base16 scheme or build-time image extraction                                                       | Seed colour or image                                              | Stock, custom JSON, wallpaper, seed colour                                                        | Static scheme library (361 base16 / 210 base24)                   | Anything (hex, base16, build-time matugen) |
| Colour model                      | base16 (16 slots)                                                                                  | Material 3 roles + base16                                         | Material 3 roles                                                                                  | base16/base24                                                     | Whatever itera defines (M3 fits DMS)       |
| Light/dark                        | One polarity per build; runtime toggle is open issue #447                                          | One variant per run                                               | Both, switchable at runtime (`isLightMode`/portal)                                                | Two separate schemes                                              | Both built; runtime switch still to design |
| itera apps covered out of the box | NixOS: GTK hint, Qt, TTY, Plymouth. HM-only: WezTerm, Zed, Nushell, mpv, DMS. No mango             | None (community templates: wezterm, zed, vivaldi, gtk, qt, mango) | GTK3/4 (Nemo, virt-manager…), Qt, mango, WezTerm, Zed, DMS + greeter. No nushell/mpv/Vivaldi/boot | Templates for wezterm, zed, gtk. No nushell/mpv/Vivaldi/mango/DMS | None until written                         |
| Build vs runtime                  | Build                                                                                              | Build (or CLI at runtime)                                         | Runtime                                                                                           | Build (tinty = runtime, impure)                                   | Build                                      |
| Reproducible / checkable in CI    | Yes                                                                                                | Yes                                                               | No (mutable `~/.config` state)                                                                    | Yes                                                               | Yes                                        |
| Maintenance health                | Very active, release-pinned to NixOS                                                               | Active, v4.2.0 Aug 2026                                           | Very active (fast-moving schema)                                                                  | Org active; nix-colors archived; base16.nix quiet but alive       | itera's own                                |
| Licence                           | MIT                                                                                                | GPL-2.0                                                           | MIT (bundles matugen GPL-2.0 as a runtime tool)                                                   | MIT (specs/schemes); tinty GPL-3.0; nix-colors GPL-3.0            | itera's                                    |
| New dependency for itera          | Yes (flake input; HM in practice)                                                                  | No (already installed by DMS)                                     | No (already running)                                                                              | base16.nix input or none (pkgs.base16-schemes)                    | No                                         |

## Implications for itera

- **Stylix and the no-HM stance are at odds.** Taking Stylix without HM means using
  it as a palette/option source plus a few NixOS targets (console, Plymouth,
  grub/limine, Qt). itera would still write its own WezTerm/Zed/Nushell/mpv/DMS
  renderers, so it would carry Stylix's option surface and release coupling while
  getting very little app coverage in return.
- **DMS + matugen is already the de facto engine at runtime.** It covers the most
  itera surfaces with zero new dependencies (GTK, Qt, mango, WezTerm, Zed, shell,
  greeter) and handles runtime light/dark and per-user state. The missing piece is
  small: itera's hjem configs need to point at DMS's output files. The cost: the
  look lives in mutable runtime state, is invisible to Nix, and may not exist on
  first login until DMS has run (`generateThemeAtStartup` defaults to true).
- **A branded _static_ look still fits DMS.** A `custom` theme JSON with separate
  `dark` and `light` palettes, set through `itera.programs.dankMaterialShell.settings`
  (`currentThemeName = "custom"`, `customThemeFile`), makes DMS push itera's colours
  through every template. Wallpaper-dynamic colour remains an opt-in for users.
- **A hand-rolled token module and DMS can work together.** One possible split:
  tokens are the source of truth in Nix (palette generated at build time, for
  example by matugen from a brand seed colour, for M3 roles in both modes). They
  render (a) a DMS custom theme file, (b) static configs for surfaces DMS does not
  reach (nushell, mpv, Vivaldi, TTY/Plymouth, Flatpak overrides), and (c) fonts,
  cursor, icons and opacity, which no engine above fully owns without HM. Whether
  the token module or DMS owns app colour files (WezTerm, Zed, GTK) is the open
  question for the contract ticket.
- **base16 alone is a poor fit for the shell.** DMS and Material 3 need about 20
  roles; base16's 16 slots must be stretched (as Stylix's DMS target does). base16
  schemes still work well as an _input_ or as a terminal ANSI palette.
- **Avoid:** nix-colors (archived) and tinty (impure runtime git clones).
- **Licence note:** matugen is GPL-2.0. Calling it as a tool (at build time or
  runtime) does not change itera's licence. Vendoring templates from DMS (MIT) or
  matugen-themes needs a per-file licence check.
