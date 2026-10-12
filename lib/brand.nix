# itera's brand assets (docs/look.md#brand-assets, ADR 0003): the Flow mark,
# the wordmark and lockup, the "Lead-in trails" wallpaper and the greeter
# image, as SVG strings filled from one mode's resolved colours
# (`(iteraLib.look.resolve osConfig name).colors.<mode>`), and their PNG
# renders through resvg.
#
# The geometry is ported from the `<script id="gen">` builders of the
# throwaway prototype, archived as the `archive/prototype/brand` tag (mark R,
# motif 18). Coordinates are computed here at eval time; Nix has no trig, so
# sin is a Taylor series. No <text>: the wordmark is paths, so nothing depends
# on a font.
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
  # `g` (0..1) grows the dots in sequence, the smaller first; 1 is the mark.
  flow =
    c: g:
    concatMapStrings
      (
        { a, col }:
        concatMapStrings
          (
            {
              da,
              r,
              i,
            }:
            let
              p = pt 50 50 35 (a + da);
              s = lib.min 1 (g * 2 - i);
            in
            lib.optionalString (s > 0) ''<circle cx="${n p.x}" cy="${n p.y}" r="${n (r * s)}" fill="${col}"/>''
          )
          [
            {
              da = -22;
              r = 1.4;
              i = 0;
            }
            {
              da = -11;
              r = 2.6;
              i = 1;
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
  markAt = c: g: flow c g + iGlyph c;
  markInner = c: markAt c 1;
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
  # The `itera` Plymouth script theme: the mark centred on `surface.base` at a
  # fifth of the screen height, its lead-in dots growing in sequence as the busy
  # indicator (one 1024² frame per step, the last the whole mark), and password,
  # question and message prompts in token colours and Roboto Flex (the font
  # `boot.plymouth.font` installs).
  plymouthTheme =
    pkgs: c:
    let
      frames = 12;
      rgb =
        hex:
        concatMapStringsSep ", " (i: n (lib.fromHexString (builtins.substring i 2 hex) / 255.0)) [
          1
          3
          5
        ];
      script = builtins.toFile "itera.script" ''
        // itera's Plymouth theme, generated by lib/brand.nix from the system look.
        Window.SetBackgroundTopColor(${rgb c.surface.base});
        Window.SetBackgroundBottomColor(${rgb c.surface.base});

        size = Window.GetHeight() * 0.2;
        for (i = 0; i < ${n frames}; i++)
          frames[i] = Image("frame-" + i + ".png").Scale(size, size);
        mark = Sprite(frames[0]);
        mark.SetX(Window.GetX() + (Window.GetWidth() - size) / 2);
        mark.SetY(Window.GetY() + (Window.GetHeight() - size) / 2);

        // The dots grow in sequence, the whole mark holds, then they start again.
        tick = 0;
        fun refresh_callback() {
          global.tick++;
          f = Math.Int(global.tick / 3) % ${n (frames + 8)};
          if (f >= ${n frames}) f = ${n (frames - 1)};
          mark.SetImage(frames[f]);
        }
        Plymouth.SetRefreshFunction(refresh_callback);

        // Prompts below the mark, messages near the bottom.
        textY = Window.GetY() + (Window.GetHeight() + size) / 2 + Window.GetHeight() * 0.04;
        prompt = Sprite();
        entry = Sprite();
        message = Sprite();
        fun place(sprite, image, y) {
          sprite.SetImage(image);
          sprite.SetX(Window.GetX() + (Window.GetWidth() - image.GetWidth()) / 2);
          sprite.SetY(y);
          sprite.SetOpacity(1);
        }
        fun show_prompt(text, value) {
          label = Image.Text(text, ${rgb c.text}, 1, "Roboto Flex 14");
          place(prompt, label, textY);
          place(entry, Image.Text(value + " ", ${rgb c.accent}, 1, "Roboto Flex 14"), textY + label.GetHeight() * 1.5);
        }
        fun display_password_callback(text, bullets) {
          dots = "";
          for (i = 0; i < bullets; i++)
            dots = dots + "•";
          show_prompt(text, dots);
        }
        fun display_question_callback(text, value) {
          show_prompt(text, value);
        }
        fun display_normal_callback() {
          prompt.SetOpacity(0);
          entry.SetOpacity(0);
        }
        fun message_callback(text) {
          place(message, Image.Text(text, ${rgb c.textMuted}, 1, "Roboto Flex 12"), Window.GetY() + Window.GetHeight() * 0.9);
        }
        Plymouth.SetDisplayPasswordFunction(display_password_callback);
        Plymouth.SetDisplayQuestionFunction(display_question_callback);
        Plymouth.SetDisplayNormalFunction(display_normal_callback);
        Plymouth.SetMessageFunction(message_callback);
      '';
    in
    pkgs.runCommand "itera-plymouth-theme" { nativeBuildInputs = [ pkgs.resvg ]; } ''
      d=$out/share/plymouth/themes/itera
      mkdir -p $d
      ${concatMapStrings (
        k:
        let
          svg = ''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">${markAt c (k / (frames - 1.0))}</svg>'';
        in
        "resvg -w 1024 -h 1024 ${svgFile "itera-plymouth-${n k}" svg} $d/frame-${n k}.png\n"
      ) (lib.range 0 (frames - 1))}
      cp ${script} $d/itera.script
      cat > $d/itera.plymouth <<EOF
      [Plymouth Theme]
      Name=itera
      Description=The itera Flow mark on the system look
      ModuleName=script

      [script]
      ImageDir=$d
      ScriptFile=$d/itera.script
      EOF
    '';
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
