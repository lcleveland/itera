# Evaluation check for the look's greeter and Flatpak surfaces
# (docs/look.md#greeter, docs/look.md#flatpaks).
#
# Asserts that the greeter takes palette, mode and image from SYSTEM tokens
# (auto shows dark, a per-user accent stays out), that `syncUser` defaults to
# null and mirrors a user when set, and that the Flatpak battery adds exactly
# one colourless global override plus the adw-gtk3 extensions.
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
  inherit (import ../lib { inherit lib; }) look brand;

  bob = {
    users.users.bob = {
      isNormalUser = true;
      home = "/home/bob";
    };
    hjem.users.bob.enable = true;
    itera.users.bob.look.colors.dark.accent = "#c0ffee";
  };

  cfg = mkConfig [ bob ];
  cfgLight = mkConfig [ { itera.look.mode = "light"; } ];
  cfgAuto = mkConfig [ { itera.look.mode = "auto"; } ];
  cfgSync = mkConfig [
    bob
    { itera.desktop.dankMaterialShell.greeter.syncUser = "bob"; }
  ];
  cfgWallpaper = mkConfig [
    { itera.desktop.dankMaterialShell.greeter.wallpaper = "/etc/login.jpg"; }
  ];
  cfgFlatpak = mkConfig [ { itera.desktop.flatpak.enable = true; } ];

  seed = c: c.itera.desktop.dankMaterialShell.greeter.seed;
  sysLook = look.resolve cfg null;
  adw = [
    "org.gtk.Gtk3theme.adw-gtk3"
    "org.gtk.Gtk3theme.adw-gtk3-dark"
  ];
  flatpakIds = c: map (p: p.appId) c.services.flatpak.packages;
in
mkCheckDrv "itera-look-greeter-eval" {
  "syncUser defaults to null" =
    cfg.itera.desktop.dankMaterialShell.greeter.syncUser == null
    && cfg.programs.dms-greeter.configHome == null;
  "the greeter uses the custom theme" = (seed cfg).settings.currentThemeName == "custom";
  "the greeter theme is the system palette, both modes" =
    (seed cfg).theme == look.dmsTheme sysLook
    && (seed cfg).theme.dark.primary == sysLook.colors.dark.accent;
  "a per-user accent does not reach the greeter" = (seed cfg).theme.dark.primary != "#c0ffee";
  "the greeter image is the system greeter image" =
    (seed cfg).settings.lockScreenWallpaperPath == "${brand.greeterPng pkgs sysLook.startColors}";
  "the greeter shows dark by default" = (seed cfg).session == { isLightMode = false; };
  "auto shows dark" = (seed cfgAuto).session == { isLightMode = false; };
  "light shows light" = (seed cfgLight).session == { isLightMode = true; };
  "the greeter wallpaper option wins over the image" =
    (seed cfgWallpaper).settings.lockScreenWallpaperPath == "/etc/login.jpg";

  "syncUser mirrors that user's DMS config" = cfgSync.programs.dms-greeter.configHome == "/home/bob";
  "syncUser mirrors that user's look" = (seed cfgSync).theme.dark.primary == "#c0ffee";
  "syncUser keeps that user's mode and wallpaper" =
    (seed cfgSync).session == null && !((seed cfgSync).settings ? lockScreenWallpaperPath);

  "no Flatpak override without the battery" = !(cfg.services.flatpak.overrides.settings ? global);
  "the global Flatpak override is exact" =
    cfgFlatpak.services.flatpak.overrides.settings.global == {
      Context.filesystems = [
        "xdg-config/gtk-3.0:ro"
        "xdg-config/gtk-4.0:ro"
      ];
      Environment.XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
    };
  "the adw-gtk3 extensions are Flatpak packages" = lib.all (
    id: builtins.elem id (flatpakIds cfgFlatpak)
  ) adw;
}
