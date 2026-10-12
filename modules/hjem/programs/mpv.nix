# itera's mpv on-screen-controller colours (home layer).
#
# The system battery `itera.desktop.videoPlayer` installs mpv. mpv has no DMS
# template and follows neither GTK nor the portal, so its OSC is themed in the
# Nix lane (docs/look.md#delivery-lanes): {file}`~/.config/mpv/script-opts/osc.conf`
# is rendered from this user's look in their starting mode (auto starts dark).
# It does not follow the DMS theme picker or a runtime light/dark switch.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`); declares
# no options and follows the system video-player toggle.
{
  lib,
  iteraLib,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.desktop.videoPlayer.enable or false;

  c = (iteraLib.look.resolve osConfig name).startColors;
in
{
  config = mkIf enable {
    xdg.config.files."mpv/script-opts/osc.conf" = {
      text = ''
        background_color=${c.background}
        timecode_color=${c.accent}
        title_color=${c.text}
        time_pos_color=${c.text}
        time_pos_outline_color=${c.background}
        buttons_color=${c.text}
        top_buttons_color=${c.text}
        small_buttonsL_color=${c.textMuted}
        small_buttonsR_color=${c.textMuted}
        held_element_color=${c.accent}
      '';
      # Explicit clobber — same rationale as the mango battery's config.conf.
      clobber = true;
    };
  };
}
