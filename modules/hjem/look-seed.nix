# The look seeder (home layer): a per-user oneshot, ordered before
# `dms.service`, that seeds the look into session state (ADR 0004,
# docs/look.md#light-dark-and-auto).
#
# DMS owns the live mode, kept in ~/.local/state/DankMaterialShell/session.json.
# The seeder merges `itera.sessionSeed` into that file (never replacing it) and
# writes the user's dconf `color-scheme`, then stamps what it seeded. It writes
# a key again only when its seeded value changes, so a live toggle or a
# wallpaper picked in the GUI survives every login until the tokens behind it
# change. An unreadable session.json fails the unit and is left alone.
#
# `itera.sessionSeed` is the extension point: this module seeds the mode and
# the wallpapers (docs/look.md#ultrawide); other slices add their session.json
# keys to it.
{
  config,
  lib,
  pkgs,
  iteraLib,
  osConfig ? null,
  name,
  programs,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.dankMaterialShell.enable or false;
  gtkOn = (osConfig.itera.enable or false) && (osConfig.itera.desktop.theme.enable or false);
  gtkScript = "${osConfig.programs.dank-material-shell.package}/share/quickshell/dms/scripts/gtk.sh";
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

  # Wallpapers (docs/look.md#ultrawide): each declared output's variant at its
  # size after rotation, keyed by connector or model, and the 16:9 variant for
  # every other output. Per mode, so DMS swaps them with the mode.
  outputs = lib.filter iteraLib.mango.keyable (
    iteraLib.mango.declaredOutputs (programs.mango.resolve osConfig name).monitors
  );
  png =
    mode: w: h:
    "${iteraLib.brand.wallpaperPng pkgs look.colors.${mode} w h}";
  wallpaperSeed = {
    perModeWallpaper = true;
    perMonitorWallpaper = outputs != [ ];
    wallpaperPathDark = png "dark" 3840 2160;
    wallpaperPathLight = png "light" 3840 2160;
    monitorWallpapersDark = lib.listToAttrs (
      map (o: lib.nameValuePair o.screen (png "dark" o.width o.height)) outputs
    );
    monitorWallpapersLight = lib.listToAttrs (
      map (o: lib.nameValuePair o.screen (png "light" o.width o.height)) outputs
    );
  };
  wallpaperKeys = builtins.toJSON (lib.attrNames wallpaperSeed);

  seed = pkgs.writeText "itera-session-seed.json" (builtins.toJSON config.itera.sessionSeed);
  seeder = pkgs.writeShellScript "itera-look-seed" ''
    set -eu
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.jq
        pkgs.dconf
        pkgs.gnused
        pkgs.gnugrep
      ]
    }
    ${lib.optionalString gtkOn ''
      # DMS themes GTK only once its "Apply GTK colors" has run: that makes the
      # user copy of adw-gtk3 that DMS patches (and then sets `gtk-theme` to)
      # after each colour run, and adds the GTK4 gtk.css import. Every login,
      # so an adw-gtk3 update is copied again.
      # ponytail: the GTK4 import needs DMS's dank-colors.css, so a new user's
      # GTK4 apps get their accent from the second login; run after dms.service
      # if that matters.
      ${pkgs.bash}/bin/bash ${gtkScript} "''${XDG_CONFIG_HOME:-$HOME/.config}" apply false >&2 || true
    ''}
    state=''${XDG_STATE_HOME:-$HOME/.local/state}
    session=$state/DankMaterialShell/session.json
    stamp=$state/itera/session-seed.json
    cmp -s ${seed} "$stamp" && exit 0
    old=$stamp
    [ -s "$old" ] || old=/dev/null

    light=${isLight}
    mkdir -p "$(dirname "$session")" "$(dirname "$stamp")"
    [ -s "$session" ] || echo '{}' > "$session"
    # Only keys whose seeded value changed since the stamp are written, so a
    # mode change keeps a wallpaper picked in the GUI and the reverse. The mode
    # (isLightMode) is seeded with any mode key; new wallpapers also become
    # the current ones for the session's mode.
    jq --slurpfile seed ${seed} --slurpfile old "$old" --argjson light "$light" \
      --argjson wallpaperKeys '${wallpaperKeys}' '
      ($seed[0] | with_entries(select(.value != $old[0][.key]))) as $new
      | ($new | keys) as $changed
      | . + (if ($changed - $wallpaperKeys) == [] then {} else {isLightMode: $light} end) + $new
      | if ($changed - ($changed - $wallpaperKeys)) == [] then . else
          (if .isLightMode then "Light" else "Dark" end) as $m
          | .wallpaperPath = .["wallpaperPath" + $m]
          | .monitorWallpapers = .["monitorWallpapers" + $m]
        end' "$session" > "$session.tmp"
    mv "$session.tmp" "$session"
    if [ "$(jq '.isLightMode == true' "$session")" = true ]; then scheme=default; else scheme=prefer-dark; fi
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
    itera.sessionSeed = modeSeed // wallpaperSeed;

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
