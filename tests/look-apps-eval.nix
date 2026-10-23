# Evaluation check for the look's bundled apps (docs/look.md#delivery-lanes).
#
# DMS lane: with DMS on, WezTerm, Zed, mango and Qt point at DMS's output and
# the binaries DMS's templates look for are on its service's PATH; with DMS off
# they keep stock colours and name no DMS file. Nix lane: mpv's osc.conf is
# rendered from the user's look, including a per-user `#c0ffee` accent.
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
    hasPkgName
    userFile
    ;

  users = {
    users.users.bob = {
      isNormalUser = true;
      home = "/home/bob";
    };
    hjem.users.bob.enable = true;
    itera.users.alice = {
      look.colors.dark.accent = "#c0ffee";
      look.radius = 4;
    };
  };

  cfg = mkConfig [ users ];
  cfgNoDms = mkConfig [
    users
    {
      itera.desktop.dankMaterialShell.enable = false;
      # DMS is what pulls mango in.
      itera.desktop.mango.enable = true;
    }
  ];
  cfgOtherZedTheme = mkConfig [
    users
    { itera.programs.zed.settings.theme = "One Dark"; }
  ];
  cfgOtherUserZedTheme = mkConfig [
    { itera.users.dave.programs.zed.settings.theme.dark = "Gruvbox Dark"; }
  ];

  inherit ((import ../lib { inherit lib; })) look;
  bobColors = (look.resolve cfg "bob").startColors;

  wezterm = c: user: userFile c user "wezterm/wezterm.lua";
  zedTheme = c: c.itera.programs.zed.settings.theme;
  mango = c: user: userFile c user "mango/config.conf";
  osc = c: user: userFile c user "mpv/script-opts/osc.conf";
  zedAsserts = c: lib.filter (a: !a.assertion && lib.hasInfix "DankShell" a.message) c.assertions;
in
mkCheckDrv "itera-look-apps-eval" {
  # WezTerm: DMS writes wezterm/colors/dank-theme.toml.
  "wezterm uses DMS's dank-theme" = lib.hasInfix "config.color_scheme = 'dank-theme'" (
    wezterm cfg "bob"
  );
  "wezterm only names dank-theme once DMS has written it" =
    lib.hasInfix "/wezterm/colors/dank-theme.toml" (wezterm cfg "bob");
  "wezterm keeps stock colours without DMS" = !(lib.hasInfix "dank-theme" (wezterm cfgNoDms "bob"));

  # Zed: DMS writes zed/themes/dank-zed-theme.json.
  "zed uses the DankShell themes" =
    (zedTheme cfg).dark == "DankShell Dark" && (zedTheme cfg).light == "DankShell Light";
  "zed keeps stock themes without DMS" =
    (zedTheme cfgNoDms).dark == "One Dark" && (zedTheme cfgNoDms).light == "One Light";
  "a system non-DMS zed theme fails while DMS is on" = zedAsserts cfgOtherZedTheme != [ ];
  "a per-user non-DMS zed theme fails while DMS is on" = zedAsserts cfgOtherUserZedTheme != [ ];
  "the default zed theme passes" = zedAsserts cfg == [ ];
  "stock zed themes pass without DMS" = zedAsserts cfgNoDms == [ ];

  # mango: dms/colors.conf, and the look's radius after DMS's fragments.
  "mango sources DMS's colours" = lib.hasInfix "source_optional=./dms/colors.conf" (mango cfg "bob");
  "mango names no DMS file without DMS" = !(lib.hasInfix "dms/" (mango cfgNoDms "bob"));
  "mango radius comes from the look" =
    lib.hasInfix "border_radius=${toString (look.resolve cfg "bob").radius}\n" (mango cfg "bob")
    && lib.hasInfix "border_radius=4\n" (mango cfg "alice");
  "mango radius follows DMS's layout fragment" =
    let
      text = mango cfg "bob";
      after = lib.last (lib.splitString "source_optional=./dms/layout.conf" text);
    in
    lib.hasInfix "border_radius=" after;

  # Qt: DMS's kcolorscheme served through qtengine.
  "qt uses qtengine with DMS" =
    cfg.environment.sessionVariables.QT_QPA_PLATFORMTHEME == "qtengine"
    && hasPkgName "qtengine" cfg.environment.systemPackages
    && cfg.qt.enable;
  "qt keeps stock theming without DMS" =
    !(cfgNoDms.environment.sessionVariables ? QT_QPA_PLATFORMTHEME)
    && !(hasPkgName "qtengine" cfgNoDms.environment.systemPackages);

  # DMS finds template apps by name on its PATH, which is the user manager's
  # (the system profile) as long as the unit sets none of its own.
  "the DMS service keeps the session PATH" = !(cfg.systemd.user.services.dms.environment ? PATH);
  "DMS's template apps are in the system profile" =
    lib.all (n: hasPkgName n cfg.environment.systemPackages)
      [
        "wezterm"
        "zed-editor"
        "mango"
      ];
  "the DMS service sees mango's instance" =
    let
      setup = lib.findFirst (lib.hasSuffix "session-setup") "" (lib.splitString "\n" (mango cfg "bob"));
    in
    lib.hasInfix "MANGO_INSTANCE_SIGNATURE" (builtins.readFile (lib.removePrefix "exec_once=" setup));

  # mpv: Nix lane, from the user's look in their starting mode.
  "mpv's osc carries the look" =
    lib.hasInfix "background_color=${bobColors.background}" (osc cfg "bob")
    && lib.hasInfix "timecode_color=${bobColors.accent}" (osc cfg "bob");
  "a per-user accent reaches mpv's osc" = lib.hasInfix "timecode_color=#c0ffee" (osc cfg "alice");
  "mpv's osc follows the look without DMS" = lib.hasInfix "timecode_color=#c0ffee" (
    osc cfgNoDms "alice"
  );
}
