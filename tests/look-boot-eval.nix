# Check for the look at boot and on the console (docs/look.md#boot-and-console).
#
# Plymouth runs the itera theme by default (and the opt-out turns it off), in
# the system look's starting mode, with a system-level `#c0ffee` override
# reaching the theme script and `console.colors`. Boot is silent by default,
# the console takes the 16 dark terminal tokens, and its Terminus size follows
# the system-declared monitors.
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
    ;
  inherit ((import ../lib { inherit lib; })) look brand;

  cfg = mkConfig [
    {
      itera.look.colors.dark = {
        accent = "#c0ffee";
        terminal.red = "#c0ffee";
      };
    }
  ];
  cfgLight = mkConfig [ { itera.look.mode = "light"; } ];
  cfgAuto = mkConfig [ { itera.look.mode = "auto"; } ];
  cfgOff = mkConfig [ { itera.boot.plymouth.enable = false; } ];
  withMonitors = monitors: mkConfig [ { itera.programs.mango.monitors = monitors; } ];

  themeOf = c: brand.plymouthTheme pkgs (look.resolve c null).startColors;
  usesTheme =
    c: c.boot.plymouth.theme == "itera" && lib.elem (themeOf c) c.boot.plymouth.themePackages;
  theme = themeOf cfg;
  # A token as the script writes it: "r, g, b" in 0..1.
  rgb =
    hex:
    lib.concatMapStringsSep ", " (i: toString (lib.fromHexString (builtins.substring i 2 hex) / 255.0))
      [
        1
        3
        5
      ];

  term = (look.resolve cfg null).colors.dark.terminal;
  slots = [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "magenta"
    "cyan"
    "white"
  ];
  sixteen = map (s: term.${s}) slots ++ map (s: term.bright.${s}) slots;

  evalChecks = mkCheckDrv "itera-look-boot-eval" {
    "plymouth runs the itera theme by default" = cfg.boot.plymouth.enable && usesTheme cfg;
    "the opt-out turns plymouth off" = !cfgOff.boot.plymouth.enable;
    "the theme follows the system mode" =
      usesTheme cfgLight && themeOf cfgLight != theme && themeOf cfgAuto == themeOf (mkConfig [ ]);
    "auto shows dark" = (look.resolve cfgAuto null).startMode == "dark";
    "prompts are in Roboto Flex" = lib.hasInfix "/RobotoFlex" cfg.boot.plymouth.font;
    # loglevel=0 is nix-mineral's, quieter than the spec's 3.
    "boot is silent" = lib.all (p: lib.elem p cfg.boot.kernelParams) [
      "quiet"
      "loglevel=0"
      "udev.log_level=3"
      "rd.systemd.show_status=auto"
    ];
    "no boot param is passed twice" = lib.unique cfg.boot.kernelParams == cfg.boot.kernelParams;
    "the opt-out drops itera's boot params" =
      !lib.elem "rd.systemd.show_status=auto" cfgOff.boot.kernelParams;
    "console.colors are the 16 dark terminal tokens" =
      cfg.console.colors == map (lib.removePrefix "#") sixteen && lib.elem "c0ffee" cfg.console.colors;
    "the console font is Terminus" = hasPkgName "terminus-font" cfg.console.packages;
    "no monitors: ter-v24n" = cfg.console.font == "ter-v24n";
    "a monitor at scale 1.5: ter-v32n" =
      (withMonitors {
        a.scale = 1;
        b.scale = 1.5;
      }).console.font == "ter-v32n";
    "monitors below scale 1.5: ter-v20n" =
      (withMonitors {
        a.scale = 1.25;
        b = { };
      }).console.font == "ter-v20n";
  };
  dir = "${theme}/share/plymouth/themes/itera";
in
pkgs.runCommand "itera-look-boot"
  {
    nativeBuildInputs = [ pkgs.file ];
  }
  ''
    : ${evalChecks}
    grep -q '^ScriptFile=${dir}/itera.script$' ${dir}/itera.plymouth
    grep -qF '${rgb (look.resolve cfg null).startColors.surface.base}' ${dir}/itera.script
    grep -qF '${rgb "#c0ffee"}' ${dir}/itera.script
    for f in ${dir}/frame-*.png; do
      file -b "$f" | grep -q "^PNG image data, 1024 x 1024," || { echo "$f: $(file -b "$f")"; exit 1; }
    done
    test -s ${dir}/frame-0.png
    test -s ${lib.escapeShellArg cfg.boot.plymouth.font}
    touch $out
  ''
