# itera's brand assets (docs/look.md#brand-assets, ADR 0003): the Flow mark,
# the wordmark and lockup, the "Lead-in trails" wallpaper and the greeter
# image, as SVG strings filled from one mode's resolved colours
# (`(iteraLib.look.resolve osConfig name).colors.<mode>`), and their PNG
# renders through resvg.
#
# The geometry is ported from the `<script id="gen">` builders of the
# throwaway `prototype/brand` branch (mark R, motif 18). Coordinates are
# computed here at eval time; Nix has no trig, so sin is a Taylor series. No
# <text>: the wordmark is paths, so nothing depends on a font.
{ lib }:
let
  inherit (lib.strings) concatMapStrings concatMapStringsSep;

  # sin of an angle in degrees, reduced to [-180, 180) then a Taylor series to
  # x^17 (error below 1e-7 at ±π).
  sin =
    d:
    let
      x = (d - 360.0 * builtins.floor ((d + 180.0) / 360.0)) * 3.141592653589793 / 180.0;
      t = n: x * x / n;
    in
    x
    * (
      1
      - t 6 * (1 - t 20 * (1 - t 42 * (1 - t 72 * (1 - t 110 * (1 - t 156 * (1 - t 210 * (1 - t 272)))))))
    );
  cos = d: sin (d + 90.0);

  lerp =
    a: b: f:
    a + (b - a) * f;
  # Angles clockwise from 3 o'clock (SVG's y points down).
  pt = cx: cy: r: a: {
    x = cx + r * cos a;
    y = cy + r * sin a;
  };
  n = toString;
  xy = p: "${n p.x} ${n p.y}";

  stroke =
    c: w:
    ''fill="none" stroke="${c}" stroke-width="${n w}" stroke-linecap="round" stroke-linejoin="round"'';

  # Monoline geometric "itera", x-height 60..100, baseline 100.
  wordmark =
    c:
    ''<g ${stroke c 9}><path d="M5 60V100M24 42V90Q24 100 34 100M15 60H34M42 80H82A20 20 0 1 0 76.14 94.14M96 60V100M96 80A20 20 0 0 1 116 60M162 80A20 20 0 1 1 122 80A20 20 0 1 1 162 80M162 60V100"/></g><circle cx="5" cy="45" r="6" fill="${c}"/>'';

  # A filled arc whose width tapers from w0 (tail) to w1 (head), round ends.
  taper =
    cx: cy: r: a0: a1: w0: w1:
    let
      ks = map (k: k / 24.0) (lib.range 0 24);
      side = sign: map (f: pt cx cy (r + sign * lerp w0 w1 f / 2) (lerp a0 a1 f)) ks;
      out = side 1;
      inn = side (-1);
    in
    "M${concatMapStringsSep "L" xy out}A${n (w1 / 2)} ${n (w1 / 2)} 0 0 1 ${xy (lib.last inn)}L${
      concatMapStringsSep "L" xy (lib.reverseList inn)
    }A${n (w0 / 2)} ${n (w0 / 2)} 0 0 1 ${xy (builtins.head out)}Z";

  # The Flow strokes (mark R, "thin tail"), each led in by two growing dots.
  flow =
    c:
    concatMapStrings
      (
        { a, col }:
        concatMapStrings
          (
            { da, r }:
            let
              p = pt 50 50 35 (a + da);
            in
            ''<circle cx="${n p.x}" cy="${n p.y}" r="${n r}" fill="${col}"/>''
          )
          [
            {
              da = -28;
              r = 1.4;
            }
            {
              da = -15;
              r = 2.6;
            }
          ]
        + ''<path d="${taper 50 50 35 a (a + 145) 1.2 11}" fill="${col}"/>''
      )
      [
        {
          a = 135;
          col = c.accent;
        }
        {
          a = -45;
          col = c.accentTertiary;
        }
      ];
  iGlyph =
    c: ''<path d="M50 47V64" ${stroke c.text 8}/><circle cx="50" cy="35" r="5" fill="${c.text}"/>'';
  markInner = c: flow c + iGlyph c;
  lockupInner = c: ''${markInner c}<g transform="translate(118 -21)">${wordmark c.text}</g>'';

  # The mark (size = its box) or the lockup (h = its height) centred on (x, y).
  place =
    x: y: size: inner:
    ''<g transform="translate(${n x} ${n y}) scale(${n (size / 100)})">${inner}</g>'';
  placeMark =
    c: x: y: size:
    place (x - size / 2) (y - size / 2) size (markInner c);
  placeLockup =
    c: x: y: h:
    place (x - 1.45 * h) (y - h / 2) h (lockupInner c);

  # "Lead-in trails" (motif 18) at W×H: two glows, two 9-dot trails curving in
  # toward the hero, which is the mark on desktops and the lockup on the
  # greeter (inside the band that survives a 32:9 crop). Scales with H.
  motif =
    c: width: height: greeter:
    let
      W = width * 1.0;
      H = height * 1.0;
      cx = W / 2;
      cy = if greeter then H * 0.36 else H / 2;
      dx = lib.max (H * 0.7) (W * 0.28);
      grad =
        id: x: y: col: o:
        ''<radialGradient id="${id}" cx="${n x}" cy="${n y}" r="${n (H * 0.9)}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${col}" stop-opacity="${n o}"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></radialGradient>'';
      rect = fill: ''<rect width="${n width}" height="${n height}" fill="${fill}"/>'';
      trail =
        rot: col:
        concatMapStrings (
          k:
          let
            f = k / 8.0;
            p = pt cx cy (lerp (H * 0.95) (H * 0.2) f) (rot + lerp 0 70 f);
          in
          ''<circle cx="${n p.x}" cy="${n p.y}" r="${n (H * lerp 0.002 0.009 f)}" fill="${col}" opacity="${n (lerp 0.25 0.9 f)}"/>''
        ) (lib.range 0 8);
    in
    ''<svg xmlns="http://www.w3.org/2000/svg" width="${n width}" height="${n height}" viewBox="0 0 ${n width} ${n height}">''
    + "<defs>${grad "ga" (cx - dx) (cy - H * 0.4) c.accent 0.2}${
      grad "gb" (cx + dx) (cy + H * 0.4) c.accentTertiary 0.13
    }</defs>"
    + rect c.background
    + rect "url(#ga)"
    + rect "url(#gb)"
    + trail 150 c.accent
    + trail (-30) c.accentTertiary
    + (if greeter then placeLockup c cx cy (H * 0.09) else placeMark c cx cy (H * 0.14))
    + "</svg>";

  svgFile = name: svg: builtins.toFile "${name}.svg" svg;
in
rec {
  # SVG strings, from one mode's resolved colours.
  mark = c: ''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">${markInner c}</svg>'';
  lockup =
    c: ''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-6 -6 302 112">${lockupInner c}</svg>'';
  wallpaper =
    c: width: height:
    motif c width height false;
  greeter = c: motif c 3840 2160 true;

  # The class fallback wallpaper sizes: standard, ultrawide, super-ultrawide.
  fallbackSizes = [
    {
      w = 3840;
      h = 2160;
    }
    {
      w = 5120;
      h = 2160;
    }
    {
      w = 5120;
      h = 1440;
    }
  ];
  iconSizes = [
    16
    24
    32
    48
    64
    128
    256
    512
  ];

  # `svg` rendered by resvg to a width×height PNG at the store path itself.
  render =
    pkgs: name: width: height: svg:
    pkgs.runCommand "${name}.png" { nativeBuildInputs = [ pkgs.resvg ]; } ''
      resvg -w ${n width} -h ${n height} ${svgFile name svg} $out
    '';

  wallpaperPng =
    pkgs: c: width: height:
    render pkgs "itera-wallpaper-${n width}x${n height}" width height (wallpaper c width height);
  greeterPng = pkgs: c: render pkgs "itera-greeter" 3840 2160 (greeter c);
  # One large PNG of the mark (strokes, lead-in dots and the i) for Plymouth.
  plymouth = pkgs: c: render pkgs "itera-plymouth-mark" 1024 1024 (mark c);
  # The mark as the `itera-logo` hicolor icon: every size in `iconSizes` plus
  # the scalable SVG.
  icon =
    pkgs: c:
    pkgs.runCommand "itera-logo" { nativeBuildInputs = [ pkgs.resvg ]; } ''
      for s in ${lib.concatMapStringsSep " " n iconSizes}; do
        mkdir -p $out/share/icons/hicolor/''${s}x$s/apps
        resvg -w $s -h $s ${svgFile "itera-logo" (mark c)} $out/share/icons/hicolor/''${s}x$s/apps/itera-logo.png
      done
      install -Dm644 ${svgFile "itera-logo" (mark c)} $out/share/icons/hicolor/scalable/apps/itera-logo.svg
    '';
}
