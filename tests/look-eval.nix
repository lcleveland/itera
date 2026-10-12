# Evaluation check for the itera look (`itera.look`, lib/look.nix).
#
# Asserts that the Tide palette reaches DMS's generated custom theme in both
# modes, that a per-user override carries through the aliases after the merge,
# that the shipped palette passes the contrast check while an override only
# warns, and that with DMS disabled no custom theme is wired.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;
  inherit ((import ../lib { inherit lib; })) look;

  users = {
    users.users.bob = {
      isNormalUser = true;
      home = "/home/bob";
    };
    hjem.users.bob.enable = true;
    itera.users.erin = {
      look.fonts.mono = "Iosevka";
      programs.wezterm.settings.font = "Fira Code";
    };
    itera.users.alice = {
      look.colors.dark.accent = "#c0ffee";
      look.fonts.mono = "Iosevka";
      programs.wezterm.settings.font_size = 14;
      programs.zed.settings.ui_font_size = 20;
    };
  };

  cfg = mkConfig [ users ];
  cfgNoDms = mkConfig [
    users
    { itera.desktop.dankMaterialShell.enable = false; }
  ];
  # One user breaks a contrast pair; the system look is untouched.
  cfgLowContrast = mkConfig [ { itera.users.carol.look.colors.light.text = "#aaaaaa"; } ];
  # The removed WezTerm font option, set system-wide and per user.
  cfgOldFont = mkConfig [ { itera.programs.wezterm.fontFamily = "Iosevka"; } ];
  cfgOldUserFont = mkConfig [ { itera.users.dave.programs.wezterm.fontFamily = "Iosevka"; } ];

  files = c: user: c.hjem.users.${user}.xdg.config.files;
  theme = user: builtins.fromJSON (files cfg user)."DankMaterialShell/itera-theme.json".text;
  dmsSettings =
    user: builtins.fromJSON (files cfg user)."DankMaterialShell/config.d/00-itera.json".text;

  wezterm = user: (files cfg user)."wezterm/wezterm.lua".text;
  zed = user: builtins.fromJSON (builtins.readFile (files cfg user)."zed/settings.json".source);
  # The pinned DMS's own mango layout defaults, which radius and gaps mirror.
  dmsLayout = builtins.readFile "${self.inputs.dms}/core/internal/config/embedded/mango-layout.conf";
in
mkCheckDrv "itera-look-eval" {
  "a per-user accent reaches DMS primary" = (theme "alice").dark.primary == "#c0ffee";
  "a per-user accent reaches surfaceTint through the alias" =
    (theme "alice").dark.surfaceTint == "#c0ffee";
  "a per-user accent stays in its mode" = (theme "alice").light.primary == "#057176";
  "DMS carries Tide dark" =
    (theme "bob").dark.primary == "#4eccd3" && (theme "bob").dark.surfaceContainer == "#151e24";
  "DMS carries Tide light" =
    (theme "bob").light.primary == "#057176" && (theme "bob").light.surfaceText == "#141c20";
  "DMS loads the custom theme" =
    (dmsSettings "bob").currentThemeName == "custom"
    && (dmsSettings "bob").customThemeFile == "~/.config/DankMaterialShell/itera-theme.json";
  "with DMS disabled no custom theme is wired" =
    !((files cfgNoDms "bob") ? "DankMaterialShell/itera-theme.json")
    && !((files cfgNoDms "bob") ? "DankMaterialShell/config.d/00-itera.json");

  "the shipped palette passes the contrast check" = look.contrastFailures look.tide == [ ];
  "a broken shipped token fails the contrast check" =
    look.contrastFailures (lib.recursiveUpdate look.tide { dark.textMuted = "#3a4045"; }) != [ ];
  "the shipped look raises no warnings" = !builtins.any (lib.hasInfix "look: ") cfg.warnings;
  "a user override that breaks a pair warns" =
    builtins.any (lib.hasPrefix "itera.users.carol.look: light text on background") cfgLowContrast.warnings;

  "radius defaults to DMS's pinned radius" =
    lib.hasInfix "border_radius=${toString cfg.itera.look.radius}\n" dmsLayout;
  "gaps default to DMS's pinned gaps" =
    lib.hasInfix "gappih=${toString cfg.itera.look.gaps}\n" dmsLayout;
  "opacity defaults to 1.0" = cfg.itera.look.opacity == 1.0;

  # Typography (docs/look.md#typography-icons-cursor): the tokens reach
  # fontconfig, DMS, WezTerm and Zed, and an app's own settings still win.
  "fontconfig defaults to the font tokens" =
    cfg.fonts.fontconfig.defaultFonts.sansSerif == [ "Roboto Flex" ]
    && cfg.fonts.fontconfig.defaultFonts.monospace == [ "itera Mono" ]
    && cfg.fonts.fontconfig.defaultFonts.emoji == [ "Noto Color Emoji" ];
  "the look's fonts are installed" =
    lib.all (n: builtins.elem n (map lib.getName cfg.fonts.packages))
      [
        "roboto-flex"
        "itera-mono"
        "noto-fonts"
        "noto-fonts-color-emoji"
      ];
  "DMS fonts follow the tokens" =
    (dmsSettings "bob").fontFamily == "Roboto Flex"
    && (dmsSettings "bob").monoFontFamily == "itera Mono"
    && (dmsSettings "bob").lockScreenFontFamily == "Roboto Flex";
  "wezterm takes font, size and opacity from the look" =
    lib.hasInfix "config.font = wezterm.font('itera Mono')" (wezterm "bob")
    && lib.hasInfix "config.font_size = 12" (wezterm "bob")
    && lib.hasInfix "config.window_background_opacity = 1" (wezterm "bob");
  "a per-user mono font reaches wezterm" = lib.hasInfix "wezterm.font('Iosevka')" (wezterm "alice");
  "wezterm's settings.font wins over the look" =
    lib.hasInfix "config.font = wezterm.font('Fira Code')" (wezterm "erin")
    && !(lib.hasInfix "config.font = 'Fira Code'" (wezterm "erin"));
  "wezterm's own settings win over the look" =
    lib.hasInfix "config.font_size = 14" (wezterm "alice")
    && !(lib.hasInfix "config.font_size = 12" (wezterm "alice"));
  "zed takes fonts and sizes from the look" =
    (zed "bob").buffer_font_family == "itera Mono"
    && (zed "bob").buffer_font_size == 16
    && (zed "bob").ui_font_family == "Roboto Flex"
    && (zed "bob").ui_font_size == 15;
  "zed's own settings win over the look" = (zed "alice").ui_font_size == 20;
  "the old wezterm fontFamily points at look.fonts.mono" =
    lib.all (c: lib.any (a: !a.assertion && lib.hasInfix "look.fonts.mono" a.message) c.assertions)
      [
        cfgOldFont
        cfgOldUserFont
      ];
}
