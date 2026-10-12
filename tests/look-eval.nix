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
    itera.users.alice.look.colors.dark.accent = "#c0ffee";
  };

  cfg = mkConfig [ users ];
  cfgNoDms = mkConfig [
    users
    { itera.desktop.dankMaterialShell.enable = false; }
  ];
  # One user breaks a contrast pair; the system look is untouched.
  cfgLowContrast = mkConfig [ { itera.users.carol.look.colors.light.text = "#aaaaaa"; } ];

  files = c: user: c.hjem.users.${user}.xdg.config.files;
  theme = user: builtins.fromJSON (files cfg user)."DankMaterialShell/itera-theme.json".text;
  dmsSettings =
    user: builtins.fromJSON (files cfg user)."DankMaterialShell/config.d/00-itera.json".text;

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
}
