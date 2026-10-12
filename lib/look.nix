# The itera look: the `itera.look` option tree, the Tide palette, the resolver
# and the WCAG contrast check. See docs/look.md.
#
# This is the only file that reads `itera.look` (a flake-check lint enforces
# it): every battery calls `resolve osConfig name` instead. It holds the
# palette, so it is also the only file allowed colour literals.
{ lib }:
let
  inherit (lib) mkOption types;
  inherit (lib.attrsets)
    attrByPath
    mapAttrs
    mapAttrsRecursive
    recursiveUpdate
    ;
  inherit (lib.strings) hasPrefix splitString;

  # Tide, hand-curated in both modes (ADR 0001). A value that is not a hex
  # colour names another token: an alias, resolved after the merge so an
  # override of the source carries through.
  tide = {
    dark = {
      background = "#0a1318";
      surface = {
        lowest = "#040c12";
        low = "#0f191e";
        base = "#151e24";
        high = "#1e282e";
        highest = "#283238";
      };
      surfaceVariant = "#2a3a44";
      inverseSurface = "text";
      text = "#e2e9ed";
      textMuted = "#a9b3b9";
      inverseText = "background";
      accent = "#4eccd3";
      accentContainer = "#034649";
      textOnAccent = "#01282a";
      textOnAccentContainer = "#c5e9eb";
      accentSecondary = "#96c1c3";
      accentTertiary = "#eba295";
      border = "#3f4950";
      borderStrong = "#68747b";
      error = "#f97770";
      warning = "#f1c961";
      success = "#86d489";
      info = "#79c0f1";
      selection = "accentContainer";
      selectionText = "textOnAccentContainer";
      scrim = "#000000";
      shadow = "#000000";
      terminal = {
        black = "surface.highest";
        red = "#f47b74";
        green = "#88d078";
        yellow = "#efca61";
        blue = "#6db0f4";
        magenta = "#d98cd2";
        cyan = "#65d2d2";
        white = "textMuted";
        bright = {
          black = "borderStrong";
          red = "#ff9b93";
          green = "#a4e596";
          yellow = "#ffe295";
          blue = "#90c6fe";
          magenta = "#eca5e5";
          cyan = "#89e7e6";
          white = "text";
        };
      };
    };
    light = {
      background = "#f6fbfe";
      surface = {
        lowest = "#ffffff";
        low = "#e8f6fe";
        base = "#e2eff7";
        high = "#dbe8f1";
        highest = "#d3e0e8";
      };
      surfaceVariant = "#c7dbe7";
      inverseSurface = "text";
      text = "#141c20";
      textMuted = "#4f5a61";
      inverseText = "background";
      accent = "#057176";
      accentContainer = "#b8e9eb";
      textOnAccent = "#ffffff";
      textOnAccentContainer = "#023032";
      accentSecondary = "#396669";
      accentTertiary = "#944b40";
      border = "#c0cdd5";
      borderStrong = "#7c8890";
      error = "#c22826";
      warning = "#9d6304";
      success = "#2e7c35";
      info = "#036eae";
      selection = "accentContainer";
      selectionText = "textOnAccentContainer";
      scrim = "#000000";
      shadow = "#000000";
      terminal = {
        black = "text";
        red = "#ba3535";
        green = "#2f751d";
        yellow = "#816501";
        blue = "#0465af";
        magenta = "#993f94";
        cyan = "#067272";
        white = "#5a656c";
        bright = {
          black = "textMuted";
          red = "#a7031a";
          green = "#1a6001";
          yellow = "#695200";
          blue = "#01518f";
          magenta = "#872082";
          cyan = "#055c5c";
          white = "#343f45";
        };
      };
    };
  };

  # The shipped font tokens (docs/look.md#typography-icons-cursor). Sizes are in
  # points; the fonts battery installs these families.
  shippedFonts = {
    sans = "Roboto Flex";
    mono = "itera Mono";
    emoji = "Noto Color Emoji";
    size = {
      sans = 11;
      mono = 12;
    };
  };

  # Replace every alias with the hex value it names, following chains.
  resolveAliases =
    palette:
    let
      go =
        seen: token: v:
        if !builtins.isString v then
          throw "itera.look: colour token `${token}` must be a hex colour or a token name"
        else if hasPrefix "#" v then
          if builtins.match "#[0-9a-fA-F]{6}" v == null then
            throw "itera.look: colour token `${token}` is `${v}`, not a #rrggbb colour"
          else
            v
        else if builtins.elem v seen then
          throw "itera.look: colour token `${token}` is part of an alias cycle"
        else
          go (seen ++ [ v ]) token (
            attrByPath (splitString "." v)
              (throw "itera.look: colour token `${token}` refers to unknown token `${v}`")
              palette
          );
    in
    mapAttrsRecursive (path: go [ ] (lib.concatStringsSep "." path)) palette;

  # WCAG 2 relative luminance through a table of linearised sRGB channel values
  # (Nix has no pow), indexed by the 0-255 channel byte.
  srgbLinear = [
    0.000000
    0.000304
    0.000607
    0.000911
    0.001214
    0.001518
    0.001821
    0.002125
    0.002428
    0.002732
    0.003035
    0.003347
    0.003677
    0.004025
    0.004391
    0.004777
    0.005182
    0.005605
    0.006049
    0.006512
    0.006995
    0.007499
    0.008023
    0.008568
    0.009134
    0.009721
    0.010330
    0.010960
    0.011612
    0.012286
    0.012983
    0.013702
    0.014444
    0.015209
    0.015996
    0.016807
    0.017642
    0.018500
    0.019382
    0.020289
    0.021219
    0.022174
    0.023153
    0.024158
    0.025187
    0.026241
    0.027321
    0.028426
    0.029557
    0.030713
    0.031896
    0.033105
    0.034340
    0.035601
    0.036889
    0.038204
    0.039546
    0.040915
    0.042311
    0.043735
    0.045186
    0.046665
    0.048172
    0.049707
    0.051269
    0.052861
    0.054480
    0.056128
    0.057805
    0.059511
    0.061246
    0.063010
    0.064803
    0.066626
    0.068478
    0.070360
    0.072272
    0.074214
    0.076185
    0.078187
    0.080220
    0.082283
    0.084376
    0.086500
    0.088656
    0.090842
    0.093059
    0.095307
    0.097587
    0.099899
    0.102242
    0.104616
    0.107023
    0.109462
    0.111932
    0.114435
    0.116971
    0.119538
    0.122139
    0.124772
    0.127438
    0.130136
    0.132868
    0.135633
    0.138432
    0.141263
    0.144128
    0.147027
    0.149960
    0.152926
    0.155926
    0.158961
    0.162029
    0.165132
    0.168269
    0.171441
    0.174647
    0.177888
    0.181164
    0.184475
    0.187821
    0.191202
    0.194618
    0.198069
    0.201556
    0.205079
    0.208637
    0.212231
    0.215861
    0.219526
    0.223228
    0.226966
    0.230740
    0.234551
    0.238398
    0.242281
    0.246201
    0.250158
    0.254152
    0.258183
    0.262251
    0.266356
    0.270498
    0.274677
    0.278894
    0.283149
    0.287441
    0.291771
    0.296138
    0.300544
    0.304987
    0.309469
    0.313989
    0.318547
    0.323143
    0.327778
    0.332452
    0.337164
    0.341914
    0.346704
    0.351533
    0.356400
    0.361307
    0.366253
    0.371238
    0.376262
    0.381326
    0.386429
    0.391572
    0.396755
    0.401978
    0.407240
    0.412543
    0.417885
    0.423268
    0.428690
    0.434154
    0.439657
    0.445201
    0.450786
    0.456411
    0.462077
    0.467784
    0.473531
    0.479320
    0.485150
    0.491021
    0.496933
    0.502886
    0.508881
    0.514918
    0.520996
    0.527115
    0.533276
    0.539479
    0.545724
    0.552011
    0.558340
    0.564712
    0.571125
    0.577580
    0.584078
    0.590619
    0.597202
    0.603827
    0.610496
    0.617207
    0.623960
    0.630757
    0.637597
    0.644480
    0.651406
    0.658375
    0.665387
    0.672443
    0.679542
    0.686685
    0.693872
    0.701102
    0.708376
    0.715694
    0.723055
    0.730461
    0.737910
    0.745404
    0.752942
    0.760525
    0.768151
    0.775822
    0.783538
    0.791298
    0.799103
    0.806952
    0.814847
    0.822786
    0.830770
    0.838799
    0.846873
    0.854993
    0.863157
    0.871367
    0.879622
    0.887923
    0.896269
    0.904661
    0.913099
    0.921582
    0.930111
    0.938686
    0.947307
    0.955973
    0.964686
    0.973445
    0.982251
    0.991102
    1.000000
  ];
  hexDigits = lib.listToAttrs (
    lib.imap0 (i: c: lib.nameValuePair c i) (lib.stringToCharacters "0123456789abcdef")
  );
  channel =
    hex: i:
    let
      d = n: hexDigits.${lib.toLower (builtins.substring n 1 hex)};
    in
    builtins.elemAt srgbLinear (16 * d i + d (i + 1));
  luminance = hex: 0.2126 * channel hex 1 + 0.7152 * channel hex 3 + 0.0722 * channel hex 5;
  contrast =
    a: b:
    let
      la = luminance a;
      lb = luminance b;
    in
    (lib.max la lb + 0.05) / (lib.min la lb + 0.05);

  # Pairs and thresholds from docs/look.md#verification: body text 7:1; other
  # text, on-colours, status and terminal colours 4.5:1; accents and
  # borderStrong 3:1. The dark terminal's black slots are background shades by
  # design, so only light checks all 16.
  onBackground =
    min:
    map (fg: {
      inherit fg min;
      bg = "background";
    });
  terminalSlots =
    lib.concatMap
      (c: [
        "terminal.${c}"
        "terminal.bright.${c}"
      ])
      [
        "red"
        "green"
        "yellow"
        "blue"
        "magenta"
        "cyan"
        "white"
      ];
  commonPairs =
    map
      (bg: {
        fg = "text";
        inherit bg;
        min = 7.0;
      })
      [
        "background"
        "surface.lowest"
        "surface.low"
        "surface.base"
        "surface.high"
      ]
    ++ [
      {
        fg = "textMuted";
        bg = "background";
        min = 4.5;
      }
      {
        fg = "textMuted";
        bg = "surface.base";
        min = 4.5;
      }
      {
        fg = "textOnAccent";
        bg = "accent";
        min = 4.5;
      }
      {
        fg = "textOnAccentContainer";
        bg = "accentContainer";
        min = 4.5;
      }
      {
        fg = "selectionText";
        bg = "selection";
        min = 4.5;
      }
      {
        fg = "inverseText";
        bg = "inverseSurface";
        min = 4.5;
      }
    ]
    ++ onBackground 4.5 (
      [
        "error"
        "warning"
        "success"
        "info"
      ]
      ++ terminalSlots
    )
    ++ onBackground 3.0 [
      "accent"
      "accentSecondary"
      "accentTertiary"
      "borderStrong"
    ];
  contrastPairs = {
    dark = commonPairs;
    light =
      commonPairs
      ++ onBackground 4.5 [
        "terminal.black"
        "terminal.bright.black"
      ];
  };

  # Two decimals, for messages.
  fmtRatio =
    r:
    let
      c = builtins.floor (r * 100);
      frac = toString (lib.mod c 100);
    in
    "${toString (c / 100)}.${if lib.stringLength frac == 1 then "0" + frac else frac}";

  # Every pair below its threshold in `colors` (aliases are resolved here), as
  # messages naming the token, the pair and the ratio.
  contrastFailures =
    colors:
    lib.concatMap
      (
        mode:
        let
          get = t: attrByPath (splitString "." t) null (resolveAliases colors.${mode});
        in
        lib.concatMap (
          p:
          let
            r = contrast (get p.fg) (get p.bg);
          in
          lib.optional (r < p.min) "${mode} ${p.fg} on ${p.bg} is ${fmtRatio r}:1, below ${fmtRatio p.min}:1"
        ) contrastPairs.${mode}
      )
      [
        "dark"
        "light"
      ];

  # Merge nested token sets one key at a time, keeping packages whole.
  deepMerge = lib.recursiveUpdateUntil (
    _: l: r:
    !(builtins.isAttrs l && builtins.isAttrs r) || lib.isDerivation l || lib.isDerivation r
  );

  # The merged look for one user (`null` = the system look): a per-user scalar
  # wins when set, colours merge one token at a time per mode over Tide (then
  # aliases resolve), fonts one key at a time over the shipped fonts, and other
  # token sets one key at a time. `startMode` is the mode a session starts in
  # (auto starts dark), and `startColors` its palette, for Nix-lane surfaces
  # that render one mode.
  resolve =
    osConfig: name:
    let
      sys = osConfig.itera.look;
      usr = if name == null then { } else osConfig.itera.users.${name}.look or { };
      pick = k: if usr.${k} or null != null then usr.${k} else sys.${k};
      merge = k: deepMerge sys.${k} (usr.${k} or { });
      mode = pick "mode";
      startMode = if mode == "light" then "light" else "dark";
      colors = mapAttrs (
        mode: shipped:
        resolveAliases (
          recursiveUpdate (recursiveUpdate shipped sys.colors.${mode}) (usr.colors.${mode} or { })
        )
      ) tide;
    in
    {
      inherit mode startMode colors;
      startColors = colors.${startMode};
      radius = pick "radius";
      gaps = pick "gaps";
      opacity = pick "opacity";
      darkFrom = pick "darkFrom";
      lightFrom = pick "lightFrom";
      latitude = pick "latitude";
      longitude = pick "longitude";
      fonts = recursiveUpdate (recursiveUpdate shippedFonts sys.fonts) (usr.fonts or { });
      cursor = merge "cursor";
      icons = merge "icons";
    };

  clock = types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]";

  colorOverrides = mkOption {
    type = types.attrsOf types.anything;
    default = { };
    description = "Token overrides for this mode.";
  };
in
{
  inherit tide resolve contrastFailures;

  # `itera.look` and `itera.users.<name>.look`, spliced in like a curated
  # program by modules/programs/look.nix, plus the contrast warnings.
  registration =
    let
      reg = (import ./programs.nix { inherit lib; }).mkCuratedProgram {
        name = "look";
        path = [ "look" ];
        fields = {
          mode = {
            type = types.enum [
              "dark"
              "light"
              "auto"
            ];
            default = "dark";
            description = ''
              The starting light/dark mode, seeded into DankMaterialShell, which
              owns the live mode: a toggle there lasts until this changes. `auto`
              follows the `darkFrom`/`lightFrom` schedule, or sunset and sunrise
              when `latitude` and `longitude` are set. Without DankMaterialShell,
              `auto` starts dark.
            '';
          };
          darkFrom = {
            type = clock;
            default = "18:00";
            description = "In `auto` mode, when dark mode starts (HH:MM).";
          };
          lightFrom = {
            type = clock;
            default = "06:00";
            description = "In `auto` mode, when light mode starts (HH:MM).";
          };
          latitude = {
            type = types.nullOr (types.numbers.between (-90) 90);
            default = null;
            description = "Latitude for `auto` mode's sunset/sunrise schedule, set with `longitude`.";
          };
          longitude = {
            type = types.nullOr (types.numbers.between (-180) 180);
            default = null;
            description = "Longitude for `auto` mode's sunset/sunrise schedule, set with `latitude`.";
          };
          colors = {
            type = types.submodule {
              options = {
                dark = colorOverrides;
                light = colorOverrides;
              };
            };
            attrs = true;
            example = {
              dark.accent = "#c0ffee";
            };
            description = ''
              Colour token overrides over the Tide palette, per mode, merged one
              token at a time (system, then per user). Values are `#rrggbb` or
              the name of another token (`"accent"`, `"surface.high"`).
              Tokens that alias another follow its override. Containers and
              on-colours are set by hand, so override the whole accent family
              together; an override that breaks a contrast pair is an eval
              warning.
            '';
          };
          fonts = {
            type = types.attrsOf types.anything;
            attrs = true;
            example = {
              mono = "Iosevka";
              size.mono = 13;
            };
            description = ''
              Font token overrides, merged one key at a time (system, then per
              user): `sans`, `mono` and `emoji` family names and `size.sans` /
              `size.mono` in points. The defaults are Roboto Flex 11 and itera
              Mono 12, with Noto Color Emoji; only those fonts are installed,
              so add the package for any other family to {option}`fonts.packages`.
            '';
          };
          radius = {
            type = types.ints.unsigned;
            # DMS's own window corner radius (its mango layout.conf default).
            default = 12;
            description = "Corner radius in pixels.";
          };
          gaps = {
            type = types.ints.unsigned;
            # DMS's own mango gap (its layout.conf default).
            default = 5;
            description = "Gap between windows in pixels.";
          };
          opacity = {
            type = types.numbers.between 0 1;
            default = 1.0;
            description = "Window opacity, from 0 to 1.";
          };
          cursor = {
            type = types.attrsOf types.anything;
            attrs = true;
            example = {
              name.dark = "Bibata-Modern-Amber";
              size = 32;
            };
            description = ''
              Cursor tokens, merged one key at a time (system, then per user):
              `package`, `name.dark`, `name.light` and `size`. The default is
              Bibata Modern Ice (dark) and Classic (light) at 24. The starting
              mode's theme reaches DMS (and so mango), `XCURSOR_*`, dconf and
              {file}`~/.Xresources`. Only the starting mode's theme is applied: DMS
              keeps one cursor theme, so a runtime mode switch doesn't change it.
            '';
          };
          icons = {
            type = types.attrsOf types.anything;
            attrs = true;
            description = ''
              Icon theme tokens, merged one key at a time (system, then per
              user): `package`, `name.dark` and `name.light`. The default is
              Papirus-Dark and Papirus-Light with teal folders, swapped per mode
              by DMS.
            '';
          };
        };
      };
    in
    {
      inherit (reg) usersSubmodule;
      systemModule =
        {
          config,
          pkgs,
          ...
        }:
        let
          sysFailures = contrastFailures (resolve config null).colors;
          oldIcons = config.itera.desktop.iconTheme;
        in
        {
          imports = [ reg.systemModule ];

          # The removed icon-theme options (docs/look.md#migration), which now
          # set the icon tokens. Drop both at NixOS 26.11, the next stable
          # release after they landed.
          options.itera.desktop.iconTheme = {
            package = mkOption {
              type = types.nullOr types.package;
              default = null;
              visible = false;
              description = "Renamed to the look's icons.package.";
            };
            name = mkOption {
              type = types.nullOr types.str;
              default = null;
              visible = false;
              description = "Replaced by the look's per-mode icons.name.";
            };
          };

          config = {
            # Shipped icon and cursor tokens. Packages need `pkgs`, so these are
            # set here rather than in resolve.
            itera.look = {
              icons = {
                package = lib.mkDefault (pkgs.papirus-icon-theme.override { color = "teal"; });
                # The old option sets both modes at normal priority, as
                # mkChangedOptionModule would.
                name =
                  if oldIcons.name != null then
                    {
                      dark = oldIcons.name;
                      light = oldIcons.name;
                    }
                  else
                    {
                      dark = lib.mkDefault "Papirus-Dark";
                      light = lib.mkDefault "Papirus-Light";
                    };
              }
              // lib.optionalAttrs (oldIcons.package != null) { inherit (oldIcons) package; };
              cursor = {
                package = lib.mkDefault pkgs.bibata-cursors;
                name = {
                  dark = lib.mkDefault "Bibata-Modern-Ice";
                  light = lib.mkDefault "Bibata-Modern-Classic";
                };
                size = lib.mkDefault 24;
              };
            };

            # The shipped palette is checked in flake check; here only overrides
            # can fail, so they warn. A user inheriting a system failure is
            # reported once, under the system.
            warnings =
              map (f: "itera.look: ${f}") sysFailures
              ++ lib.concatMap (
                n:
                map (f: "itera.users.${n}.look: ${f}") (
                  lib.subtractLists sysFailures (contrastFailures (resolve config n).colors)
                )
              ) (lib.attrNames config.itera.users)
              ++ lib.optional (
                oldIcons.package != null
              ) "itera.desktop.iconTheme.package has been renamed to itera.look.icons.package."
              ++
                lib.optional (oldIcons.name != null)
                  "itera.desktop.iconTheme.name has been replaced by itera.look.icons.name.dark and .light; it sets both."
              # Auto needs DMS to switch; without it the batteries start dark.
              ++
                lib.optional
                  (
                    !config.itera.desktop.dankMaterialShell.enable
                    && lib.any (n: (resolve config n).mode == "auto") ([ null ] ++ lib.attrNames config.itera.users)
                  )
                  "itera.look: mode = \"auto\" needs DankMaterialShell to switch; with it disabled the session starts dark.";
          };
        };
    };
}
