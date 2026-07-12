# itera's audio battery.
#
# The PipeWire server itself already comes up via `services.graphical-desktop`
# (pulled in by the mango module) — sockets, ALSA, PulseAudio compat and
# WirePlumber are all on. The one piece that stays off is realtime scheduling,
# so PipeWire runs at normal priority and glitches (xruns) under load. This
# battery adds the missing `security.rtkit`, which PipeWire uses to request
# realtime priority. It does NOT re-declare PipeWire.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# with `mkDefault`, so it is on by default yet overridable.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.audio;
in
{
  options.itera.audio = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Grant the audio server realtime scheduling via rtkit.";
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    security.rtkit.enable = mkDefault true;

    # rtkit only helps if there is actually a realtime-capable audio server to
    # ask for priority. PipeWire is expected from the desktop stack; flag it if
    # someone has turned the server off but left this on.
    warnings = lib.optional (!config.services.pipewire.enable) ''
      itera.audio is enabled (rtkit) but services.pipewire is off — rtkit will
      have no audio server to grant realtime priority to.
    '';
  };
}
