# itera's GUI file-manager battery (Nemo).
#
# Native NixOS/nixpkgs feature (no flake input): installs Nemo (Cinnamon's file
# manager) with its extensions, plus the services it leans on — gvfs for
# trash/network mounts/removable-drive automounting, and tumbler for thumbnails —
# and makes it the session's default handler for directories on the
# mango/DankMaterialShell desktop.
#
# Nemo runs fine on wlroots and pulls only a small slice of the GTK/Cinnamon stack
# (far less than full GNOME/Nautilus). There is no system state to persist under
# impermanence — per-user Nemo settings live in $HOME (covered by the hjem /
# `itera.impermanence.users` home-persistence path).
#
# Opt-OUT (default ON): set `itera.desktop.fileManager.enable = false` to drop it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkPackageOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types) bool;

  cfg = config.itera.desktop.fileManager;
in
{
  options.itera.desktop.fileManager = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install the Nemo GUI file manager (with gvfs mounting/trash and tumbler
        thumbnails) and make it the default directory handler. On by default
        whenever {option}`itera.enable` is set; set to `false` to opt out.
      '';
    };

    # `nullable = true` lets a consumer drop the package (e.g. to supply their own
    # file-manager build) while keeping the gvfs/tumbler/handler wiring below.
    # nemo-with-extensions bundles nemo-fileroller (archives), nemo-preview, etc.
    package = mkPackageOption pkgs "nemo-with-extensions" { nullable = true; };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    environment.systemPackages = mkIf (cfg.package != null) [ cfg.package ];

    # gvfs: trash, network shares, removable-drive automounting. tumbler:
    # thumbnail generation. dconf: where Nemo/Cinnamon store their settings.
    services.gvfs.enable = mkDefault true;
    services.tumbler.enable = mkDefault true;
    programs.dconf.enable = mkDefault true;

    # Make Nemo the session's default file manager for directories.
    xdg.mime.defaultApplications."inode/directory" = mkDefault "nemo.desktop";
  };
}
