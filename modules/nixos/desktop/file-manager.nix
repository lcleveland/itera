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
    # `wsdd` backs gvfs's WS-Discovery backend (`gvfsd-wsdd`) — what actually
    # finds Windows/SMB hosts under Nemo's "Network". gvfs ships that backend
    # with `AutoMount=true` and spawns the daemon by bare name off PATH, but
    # nixpkgs puts no `wsdd` there, so opening Network logs "Failed to spawn the
    # wsdd daemon … No such file or directory" plus "Couldn't create directory
    # monitor on wsdd:///" and silently discovers nothing. Same shape as the
    # avahi/nss-mdns gap fixed in the DankMaterialShell battery: the feature was
    # advertised with nothing behind it. Client side only — this discovers other
    # hosts, it does NOT advertise this one on the LAN (that would be
    # `services.samba-wsdd`, deliberately left off on a hardened desktop).
    environment.systemPackages =
      lib.optional (cfg.package != null) cfg.package
      ++ lib.optional config.services.gvfs.enable pkgs.wsdd;

    # gvfs: trash, network shares, removable-drive automounting. tumbler:
    # thumbnail generation. dconf: where Nemo/Cinnamon store their settings.
    services.gvfs.enable = mkDefault true;
    services.tumbler.enable = mkDefault true;
    programs.dconf.enable = mkDefault true;

    # Make Nemo the session's default file manager for directories.
    xdg.mime.defaultApplications."inode/directory" = mkDefault "nemo.desktop";
  };
}
