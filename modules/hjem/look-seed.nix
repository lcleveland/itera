# The look seeder (home layer): a per-user oneshot, ordered before
# `dms.service`, that seeds the look into session state (ADR 0004,
# docs/look.md#light-dark-and-auto).
#
# DMS owns the live mode, kept in ~/.local/state/DankMaterialShell/session.json.
# The seeder merges `itera.sessionSeed` into that file (never replacing it) and
# writes the user's dconf `color-scheme`, then stamps what it seeded. It runs
# again only when the seed changes, so a live toggle survives every login until
# the configuration itself changes. An unreadable session.json fails the unit
# and is left alone.
#
# `itera.sessionSeed` is the extension point: this module seeds the mode, and
# other look slices (wallpapers) add their session.json keys to it.
{
  config,
  lib,
  pkgs,
  iteraLib,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.dankMaterialShell.enable or false;
  look = iteraLib.look.resolve osConfig name;

  hm = t: map lib.toIntBase10 (lib.splitString ":" t);
  hhmm = t: lib.replaceStrings [ ":" ] [ "" ] t;
  located = look.latitude != null && look.longitude != null;

  # DMS's session.json keys for the mode (its SessionSpec.js).
  modeSeed =
    if look.mode != "auto" then
      {
        isLightMode = look.mode == "light";
        themeModeAutoEnabled = false;
      }
    else if located then
      {
        themeModeAutoEnabled = true;
        themeModeAutoMode = "location";
        inherit (look) latitude longitude;
        nightModeUseIPLocation = false;
      }
    else
      let
        dark = hm look.darkFrom;
        light = hm look.lightFrom;
      in
      {
        themeModeAutoEnabled = true;
        themeModeAutoMode = "time";
        themeModeStartHour = builtins.elemAt dark 0;
        themeModeStartMinute = builtins.elemAt dark 1;
        themeModeEndHour = builtins.elemAt light 0;
        themeModeEndMinute = builtins.elemAt light 1;
        themeModeShareGammaSettings = false;
      };

  # Under auto, the seeded mode is the schedule's at login; DMS takes over once
  # it starts.
  # ponytail: location mode guesses from the time schedule too, until DMS
  # computes sunset; port a sunrise formula if the first seconds matter.
  isLight =
    if look.mode != "auto" then
      lib.boolToString (look.mode == "light")
    else
      let
        l = hhmm look.lightFrom;
        d = hhmm look.darkFrom;
      in
      ''$(now=$(date +%H%M); if [ ${l} -le ${d} ]; then [ "$now" -ge ${l} ] && [ "$now" -lt ${d} ]; else [ "$now" -ge ${l} ] || [ "$now" -lt ${d} ]; fi && echo true || echo false)'';

  seed = pkgs.writeText "itera-session-seed.json" (builtins.toJSON config.itera.sessionSeed);
  seeder = pkgs.writeShellScript "itera-look-seed" ''
    set -eu
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.jq
        pkgs.dconf
      ]
    }
    state=''${XDG_STATE_HOME:-$HOME/.local/state}
    session=$state/DankMaterialShell/session.json
    stamp=$state/itera/session-seed.json
    cmp -s ${seed} "$stamp" && exit 0

    light=${isLight}
    mkdir -p "$(dirname "$session")" "$(dirname "$stamp")"
    [ -s "$session" ] || echo '{}' > "$session"
    jq --slurpfile seed ${seed} --argjson light "$light" \
      '. + {isLightMode: $light} + $seed[0]' "$session" > "$session.tmp"
    mv "$session.tmp" "$session"
    if $light; then scheme=default; else scheme=prefer-dark; fi
    dconf write /org/gnome/desktop/interface/color-scheme "'$scheme'"
    install -m 644 ${seed} "$stamp"
  '';
in
{
  options.itera.sessionSeed = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    internal = true;
    description = "Keys the look seeder merges into DMS's session.json.";
  };

  config = mkIf enable {
    itera.sessionSeed = modeSeed;

    systemd.services.itera-look-seed = {
      description = "Seed the itera look into DankMaterialShell's session";
      wantedBy = [ "dms.service" ];
      before = [ "dms.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = seeder;
      };
    };
  };
}
