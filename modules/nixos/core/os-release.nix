# itera's logo in os-release (docs/look.md#brand-assets): installs the Flow
# mark as the `itera-logo` hicolor icon and points os-release's LOGO at it, so
# tools that show the distro logo (fastfetch, hostnamectl, settings panels)
# show itera's. `ID` stays `nixos`.
#
# System tokens in the starting mode (auto starts dark): per-user look
# overrides don't reach it. Gated on the master `itera.enable` with
# `mkDefault`, so it is on by default and overridable.
{
  config,
  lib,
  pkgs,
  iteraLib,
  ...
}:
{
  config = lib.mkIf config.itera.enable {
    environment.systemPackages = [
      (iteraLib.brand.icon pkgs (iteraLib.look.resolve config null).startColors)
    ];
    system.nixos.extraOSReleaseArgs.LOGO = lib.mkDefault "itera-logo";
  };
}
