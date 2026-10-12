# itera Mono: Roboto Mono with Fira Code's ligatures (Ligaturizer) and the Nerd
# Font glyphs (nerd-font-patcher), renamed and shipped under the OFL with every
# upstream notice kept. See docs/look.md#typography-icons-cursor.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchzip,
  fetchurl,
  fontforge,
  nerd-font-patcher,
  roboto-mono,
}:
let
  ligaturizer = fetchFromGitHub {
    owner = "ToxicFrog";
    repo = "Ligaturizer";
    rev = "c4065187a544a8fab40826fc91db1c6180a2d342";
    hash = "sha256-89/6xEBybIG9OfeOkwh8bwvQpp8+SOCbUxIlqbdkvqU=";
  };
  # The static weights: nixpkgs' fira-code ships only the variable font, which
  # Ligaturizer can't read ligatures from.
  firaCode = fetchzip {
    url = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip";
    stripRoot = false;
    hash = "sha256-UHOwZL9WpCHk6vZaqI/XfkZogKgycs5lWg1p0XdQt0A=";
  };
  firaLicense = fetchurl {
    url = "https://raw.githubusercontent.com/tonsky/FiraCode/6.2/LICENSE";
    hash = "sha256-HUHhADGrElMCeAoF7EyR0hjkfbDH43zzFczl5gjNwlw=";
  };
  robotoLicense = fetchurl {
    url = "https://raw.githubusercontent.com/googlefonts/RobotoMono/895ec691990d041dd727c7b5afa3ce56525d98e6/OFL.txt";
    hash = "sha256-UKuN1UaA00c/ZJyduG/s6IQ00JfHg0R1wcctL4xCkhU=";
  };
  # Roboto Mono style -> the Fira Code weight its ligatures come from (Fira Code
  # has no italics).
  styles = {
    Regular = "Regular";
    Italic = "Regular";
    Bold = "Bold";
    BoldItalic = "Bold";
  };
in
stdenvNoCC.mkDerivation {
  pname = "itera-mono";
  version = "${roboto-mono.version}-${nerd-font-patcher.version}";

  dontUnpack = true;
  nativeBuildInputs = [
    fontforge
    nerd-font-patcher
  ];

  buildPhase = ''
    runHook preBuild
    # fontforge 20251009 segfaults generating Fira Code 6's `<~>` ligature, so
    # that one is dropped.
    cp -r --no-preserve=mode ${ligaturizer} ligaturizer
    sed -i '/^    {   # <~>$/,/^    },$/d' ligaturizer/ligatures.py
    mkdir liga patched
    ${lib.concatStrings (
      lib.mapAttrsToList (style: fira: ''
        fontforge -lang=py -script ligaturizer/ligaturize.py \
          ${roboto-mono}/share/fonts/truetype/RobotoMono-${style}.ttf \
          --ligature-font-file ${firaCode}/ttf/FiraCode-${fira}.ttf \
          --output-name 'itera Mono' --prefix "" --output-dir liga
      '') styles
    )}
    for f in liga/*.ttf; do
      nerd-font-patcher --complete --makegroups -1 --outputdir patched "$f"
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/fonts/truetype patched/*.ttf
    licenses=$out/share/licenses/itera-mono
    install -Dm644 ${robotoLicense} $licenses/RobotoMono-OFL.txt
    install -Dm644 ${firaLicense} $licenses/FiraCode-OFL.txt
    for l in ${nerd-font-patcher}/share/glyphs/*/LICENSE*; do
      install -Dm644 "$l" "$licenses/nerd-fonts/$(basename "$(dirname "$l")")-$(basename "$l")"
    done
    runHook postInstall
  '';

  meta = {
    description = "Roboto Mono with Fira Code ligatures and Nerd Font glyphs";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
