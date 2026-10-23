# Check for the itera brand assets (lib/brand.nix, docs/look.md#brand-assets).
#
# Every asset renders, in both modes, at exactly the pixel size requested (no
# goldens), carries its token colours and no <text>. A per-user accent reaches
# that user's wallpapers and launcher logo, while the os-release icon follows
# the system tokens.
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
  inherit ((import ../lib { inherit lib; })) look brand;

  cfg = mkConfig [
    {
      users.users.bob = {
        isNormalUser = true;
        home = "/home/bob";
      };
      hjem.users.bob.enable = true;
      itera.users.alice.look.colors.dark.accent = "#c0ffee";
    }
  ];
  sys = look.resolve cfg null;
  alice = look.resolve cfg "alice";

  dmsSettings =
    user: builtins.fromJSON (userFile cfg user "DankMaterialShell/config.d/00-itera.json");
  launcher =
    user:
    lib.findFirst (w: w.id or null == "launcherButton") { }
      (builtins.head (dmsSettings user).barConfigs).leftWidgets;

  modes = [
    "dark"
    "light"
  ];
  hasAll = svg: lib.all (c: lib.hasInfix c svg);
  svgs = lib.concatMap (
    m:
    let
      c = sys.colors.${m};
    in
    [
      (brand.mark c)
      (brand.lockup c)
      (brand.wallpaper c 3840 2160)
      (brand.greeter c)
    ]
  ) modes;

  evalChecks = mkCheckDrv "itera-look-brand-eval" {
    "the mark carries accent, tertiary and text" = lib.all (
      m:
      hasAll (brand.mark sys.colors.${m}) (
        with sys.colors.${m};
        [
          accent
          accentTertiary
          text
        ]
      )
    ) modes;
    "the lockup carries the wordmark in text" = hasAll (brand.lockup sys.colors.dark) [
      sys.colors.dark.text
      "translate(118 -21)"
    ];
    "the wallpaper carries background, accent and tertiary" = lib.all (
      m:
      hasAll (brand.wallpaper sys.colors.${m} 5120 1440) (
        with sys.colors.${m};
        [
          background
          accent
          accentTertiary
        ]
      )
    ) modes;
    "nothing depends on a font" = !lib.any (lib.hasInfix "<text") svgs;
    "a per-user accent reaches that user's wallpaper" = lib.hasInfix "#c0ffee" (
      brand.wallpaper alice.colors.dark 3840 2160
    );
    "the launcher logo is custom" =
      (launcher "bob").launcherLogoMode == "custom" && (launcher "bob").launcherLogoCustomPath != "";
    "a per-user accent changes the launcher logo" =
      (launcher "alice").launcherLogoCustomPath != (launcher "bob").launcherLogoCustomPath;
    "os-release names the logo" =
      lib.hasInfix ''LOGO="itera-logo"''
        cfg.environment.etc."os-release".text;
    "os-release keeps ID=nixos" = lib.hasInfix "\nID=nixos\n" cfg.environment.etc."os-release".text;
    "the logo icon follows system tokens" =
      lib.any (p: p == brand.icon pkgs sys.startColors) cfg.environment.systemPackages
      && hasPkgName "itera-logo" cfg.environment.systemPackages;
  };

  # Every PNG asset with the size it must have.
  sized = lib.concatMap (
    m:
    let
      c = sys.colors.${m};
      wp = w: h: {
        png = brand.wallpaperPng pkgs c w h;
        inherit w h;
      };
    in
    map (s: wp s.w s.h) brand.fallbackSizes
    ++ [
      # A rotated portrait monitor: any declared size renders exactly.
      (wp 1080 1920)
      {
        png = brand.greeterPng pkgs c;
        w = 3840;
        h = 2160;
      }
      {
        png = "${brand.plymouthTheme pkgs c}/share/plymouth/themes/itera/frame-11.png";
        w = 1024;
        h = 1024;
      }
    ]
    ++ map (s: {
      png = "${brand.icon pkgs c}/share/icons/hicolor/${toString s}x${toString s}/apps/itera-logo.png";
      w = s;
      h = s;
    }) brand.iconSizes
  ) modes;
in
pkgs.runCommand "itera-look-brand"
  {
    nativeBuildInputs = [ pkgs.file ];
  }
  ''
    : ${evalChecks}
    check() {
      file -b "$1" | grep -q "^PNG image data, $2 x $3," || { echo "$1: $(file -b "$1"), want $2 x $3"; exit 1; }
    }
    ${lib.concatMapStrings (a: "check ${a.png} ${toString a.w} ${toString a.h}\n") sized}
    test -s ${brand.icon pkgs sys.startColors}/share/icons/hicolor/scalable/apps/itera-logo.svg
    touch $out
  ''
