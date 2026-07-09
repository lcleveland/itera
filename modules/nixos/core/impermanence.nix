# itera's ephemeral-root ("impermanence") battery.
#
# Puts `/` on tmpfs so it is wiped on every boot, and persists only an explicit
# set of paths to a real filesystem via nix-community/impermanence (bundled by
# `modules/nixos/default.nix`). Pair it with `itera.disko`, whose default layout
# already provides the on-disk `/nix` and `/persist` this module relies on.
#
# `method` is an enum currently fixed to "tmpfs" so btrfs/zfs blank-snapshot
# rollback can be added later without changing the interface.
#
# Composition: `itera.disko` still declares a `/` btrfs subvolume so it boots
# standalone; when this module is also enabled its `mkForce` tmpfs `/` wins and
# that subvolume simply goes unused. The two features never reference each other.
#
# Opt-OUT: on automatically with `itera.enable`, gated on
# `itera.enable && cfg.enable`. Enabling it puts `/` on tmpfs (wiped every boot),
# so it expects a real `/persist` mount to exist — `itera.disko`'s default layout
# provides one. Set `itera.impermanence.enable = false` to keep a persistent
# root. The curated persisted-path set is separately opt-out via `defaults.enable`.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault mkForce;
  inherit (lib.types)
    enum
    str
    listOf
    either
    attrs
    attrsOf
    submodule
    ;

  cfg = config.itera.impermanence;

  # Curated "batteries" — the paths a typical host must keep across reboots.
  # Included only when `cfg.defaults.enable`; a consumer can drop the set and
  # declare everything themselves.
  curatedDirectories = [
    "/var/log"
    "/var/lib/nixos"
    "/var/lib/systemd/coredump"
  ];
  curatedFiles = [
    "/etc/machine-id"
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key.pub"
    "/etc/ssh/ssh_host_rsa_key"
    "/etc/ssh/ssh_host_rsa_key.pub"
  ];

  # impermanence entries are either a bare path string or an attrset carrying
  # ownership/mode, for both the system- and per-user scopes.
  entryType = listOf (either str attrs);
in
{
  options.itera.impermanence = {
    enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to run an ephemeral (tmpfs) root with explicit persistence. On by
        default whenever {option}`itera.enable` is set; expects a real
        {option}`persistRoot` mount to exist. Set to `false` for a persistent root.
      '';
    };

    method = mkOption {
      type = enum [ "tmpfs" ];
      default = "tmpfs";
      description = ''
        How the root filesystem is made ephemeral. Only `tmpfs` (root in RAM,
        wiped every boot) is implemented today; the option is an enum so
        snapshot-rollback methods can be added later.
      '';
    };

    persistRoot = mkOption {
      type = str;
      default = "/persist";
      description = ''
        Directory on a real filesystem where persisted paths are stored. Must be
        a mountpoint available at boot — `itera.disko`'s default layout provides
        it as a btrfs subvolume.
      '';
    };

    tmpfsSize = mkOption {
      type = str;
      default = "2G";
      description = "Size of the tmpfs mounted at {file}`/` (the `size=` mount option).";
    };

    defaults.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Persist itera's curated set of paths (system logs, machine-id, SSH host
        keys). Set to `false` to persist only what you declare explicitly.
      '';
    };

    directories = mkOption {
      type = entryType;
      default = [ ];
      example = [ "/var/lib/tailscale" ];
      description = "Extra directories to persist, merged with the curated defaults.";
    };

    files = mkOption {
      type = entryType;
      default = [ ];
      example = [ "/etc/nix/id_rsa" ];
      description = "Extra files to persist, merged with the curated defaults.";
    };

    users = mkOption {
      type = attrsOf (submodule {
        options = {
          directories = mkOption {
            type = entryType;
            default = [ ];
            description = "Directories under a user's home to persist.";
          };
          files = mkOption {
            type = entryType;
            default = [ ];
            description = "Files under a user's home to persist.";
          };
        };
      });
      default = { };
      example = {
        alice.directories = [
          ".ssh"
          ".local/share/keyrings"
        ];
      };
      description = ''
        Per-user persisted paths, resolved relative to each user's home and mapped
        to {option}`environment.persistence.<root>.users.<name>`.
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.method == "tmpfs";
        message = "itera.impermanence.method \"${cfg.method}\" is not implemented — only \"tmpfs\" is supported.";
      }
    ];

    fileSystems = {
      # Root in RAM, wiped every boot. mkForce overrides any `/` from disko.
      "/" = mkForce {
        device = "none";
        fsType = "tmpfs";
        options = [
          "defaults"
          "size=${cfg.tmpfsSize}"
          "mode=755"
        ];
      };

      # The store and the persist root must be mounted before stage-2 activation
      # bind-mounts persisted paths back into the fresh tmpfs root.
      "/nix".neededForBoot = mkDefault true;
      ${cfg.persistRoot}.neededForBoot = mkDefault true;
    };

    environment.persistence.${cfg.persistRoot} = {
      hideMounts = mkDefault true;
      directories = (lib.optionals cfg.defaults.enable curatedDirectories) ++ cfg.directories;
      files = (lib.optionals cfg.defaults.enable curatedFiles) ++ cfg.files;
      inherit (cfg) users;
    };
  };
}
