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
# Home directories: a curated subset of every normal user's $HOME (`.config`,
# `.local/share`, `.local/state`, `.cache`, `.ssh`, `Documents`, plus `.librewolf`
# when the browser battery is on) is persisted by default so desktop/login state
# survives the wiped root with no per-user wiring. This reads the account set from
# `config.users.users` (filtered to normal users) — the same cross-battery
# introspection the module already does for secureBoot/flatpak/virtualisation —
# and merges those curated paths with any explicit `itera.impermanence.users.<name>`
# entries. Opt out via `homes.enable`.
#
# Opt-OUT: on automatically with `itera.enable`, gated on
# `itera.enable && cfg.enable`. Enabling it puts `/` on tmpfs (wiped every boot),
# so it expects a real `/persist` mount to exist — `itera.disko`'s default layout
# provides one. Set `itera.impermanence.enable = false` to keep a persistent
# root. The curated persisted-path set is separately opt-out via `defaults.enable`,
# and per-user home persistence via `homes.enable`.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules)
    mkIf
    mkDefault
    mkForce
    mkMerge
    ;
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
    "/etc/NetworkManager/system-connections" # NM connection profiles + Wi-Fi PSKs
    "/var/lib/NetworkManager" # NM leases, seen-bssids, secret_key
    "/var/lib/systemd/timesync" # timesyncd clock state
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

  # The effective set of persisted files (curated defaults + consumer additions),
  # used to decide whether /etc/machine-id is being persisted (see the
  # systemd-machine-id-commit handling in the config body).
  persistedFiles = (lib.optionals cfg.defaults.enable curatedFiles) ++ cfg.files;
  machineIdPersisted = builtins.elem "/etc/machine-id" (map (f: f.file or f) persistedFiles);

  # Curated per-user home persistence: apply `cfg.homes.{directories,files}` to
  # every normal user's home. Keyed on `config.users.users` so both itera.users
  # accounts and plain users.users normal users are covered. Merged (not replacing)
  # with any explicit `cfg.users.<name>` in the config body below.
  homeUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;
  # Append the LibreWolf profile dir when the browser battery is on — it lives at
  # ~/.librewolf, none of the curated home dirs, so bookmarks/logins/history would
  # be lost each boot otherwise. Gated so nothing is persisted when the browser is
  # dropped, mirroring the conditional system-dir additions below.
  homeDirectories =
    cfg.homes.directories ++ lib.optional config.itera.desktop.browser.enable ".librewolf";
  autoUsers = lib.mapAttrs (_: _: {
    directories = homeDirectories;
    inherit (cfg.homes) files;
  }) homeUsers;
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
        keys, NetworkManager connections, and clock state). Set to `false` to
        persist only what you declare explicitly.
      '';
    };

    accounts.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Persist the mutable account databases ({file}`/etc/passwd`,
        {file}`/etc/group`, {file}`/etc/shadow`, {file}`/etc/gshadow`) across the
        wiped tmpfs root, so {command}`passwd` password changes (and any other
        mutable-user edits) survive reboots. Without this, {file}`/etc/shadow`
        regenerates from the declarative config on every boot and password
        changes are silently lost. Set to `false` to keep account state fully
        declarative (e.g. with `users.mutableUsers = false` and a
        `hashedPasswordFile`).
      '';
    };

    homes = {
      enable = mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Persist a curated subset of every normal user's home directory across
          reboots. Set to `false` to persist nothing from homes unless you declare
          it explicitly under {option}`itera.impermanence.users.<name>`.
        '';
      };

      directories = mkOption {
        type = entryType;
        default = [
          ".config"
          ".local/share"
          ".local/state"
          ".cache"
          {
            directory = ".ssh";
            mode = "0700";
          } # owner-only; SSH rejects lax perms
          "Documents"
        ];
        description = "Home-relative directories persisted for each user when {option}`homes.enable` is set.";
      };

      files = mkOption {
        type = entryType;
        default = [ ];
        description = "Home-relative files persisted for each user when {option}`homes.enable` is set.";
      };
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
      {
        # accounts persistence hooks the traditional perl `users` activation
        # script; systemd-sysusers / userborn write /etc/shadow from a service
        # instead, so the activation-order dependency below would not apply.
        assertion =
          !cfg.accounts.enable || (!config.systemd.sysusers.enable && !config.services.userborn.enable);
        message = "itera.impermanence.accounts.enable relies on the traditional perl users activation and is incompatible with systemd.sysusers/services.userborn — disable one of them.";
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
    }
    # nix-mineral's filesystem hardening (bundled, on by default via
    # `itera.hardening`) bind-mounts /etc, /var, /home, … as shadow mounts over the
    # ephemeral tmpfs root. impermanence bind-mounts persisted paths into those same
    # trees during stage-2 activation and asserts every filesystem hosting a
    # persisted path is neededForBoot. Propagate it to the hardened bind mounts so
    # the two batteries compose. `optionalAttrs` keeps this empty — no phantom
    # fileSystems entry lacking a device — when hardening is off. `m.options.bind`
    # skips /boot, which nix-mineral leaves as a real partition, not a shadow mount.
    // lib.optionalAttrs config.nix-mineral.enable (
      lib.mapAttrs (_: _: { neededForBoot = mkDefault true; }) (
        lib.filterAttrs (_: m: m.enable && (m.options.bind or false)) config.nix-mineral.filesystems.normal
      )
    );

    environment.persistence.${cfg.persistRoot} = {
      hideMounts = mkDefault true;
      directories =
        (lib.optionals cfg.defaults.enable curatedDirectories)
        # Persist state owned by other itera batteries when they are on, so their
        # data survives the wiped root: Secure Boot signing keys, Flatpak installs,
        # and libvirt VM domains/pools/nvram.
        ++ lib.optional config.itera.secureBoot.enable config.itera.secureBoot.pkiBundle
        ++ lib.optional config.itera.desktop.flatpak.enable "/var/lib/flatpak"
        ++ lib.optional config.itera.virtualisation.enable "/var/lib/libvirt"
        # BlueZ stores device pairings under /var/lib/bluetooth; without this every
        # paired device (keyboard, headphones, …) must be re-paired after each boot.
        # Gated on the switch that actually creates the dir.
        ++ lib.optional config.hardware.bluetooth.enable "/var/lib/bluetooth"
        # fprintd stores enrolled fingerprints under /var/lib/fprint; without this
        # every finger must be re-enrolled after each boot. Gated on fprintd being
        # on (what the fingerprint battery enables and what creates the dir).
        ++ lib.optional config.services.fprintd.enable "/var/lib/fprint"
        # The DMS greeter's cache dir holds .local/state/memory.json — the last
        # successful username/session the greeter pre-selects. Persist it so the
        # greeter remembers the last user across the wiped tmpfs root. Gated on
        # the upstream greeter option, which is exactly what creates the dir (via
        # its own tmpfiles rule) and sets its greeter:greeter ownership.
        ++ lib.optional config.programs.dank-material-shell.greeter.enable "/var/lib/dms-greeter"
        ++ cfg.directories;
      files = persistedFiles;
      # Curated per-user home persistence (when homes.enable) merged with any
      # explicit itera.impermanence.users.<name>. The impermanence `users`
      # submodule's directories/files are list options, so both definitions
      # concatenate — explicit entries ADD to the curated default, not replace it.
      users = mkMerge [
        cfg.users
        (mkIf cfg.homes.enable autoUsers)
      ];
    };

    # nix-mineral shadow-bind-mounts /etc over the tmpfs root while impermanence
    # bind-mounts the persisted /etc/machine-id on top. systemd-machine-id-commit
    # write-and-unmounts /etc/machine-id on every boot systemd deems a "first
    # boot" — which is EVERY boot until a committed id lands in /persist, and the
    # unmount fails underneath the /etc shadow mount (fatal on the reformat-on-
    # boot dev VM). So mask commit when the /etc shadow mount is present AND
    # machine-id is persisted, and do the persist ourselves below.
    systemd.services.systemd-machine-id-commit.enable = mkIf (
      config.nix-mineral.enable && machineIdPersisted
    ) (mkDefault false);

    system.activationScripts = {
      # Masking commit means systemd never writes the first-boot machine-id back to
      # /persist — a fresh disko install ships /persist/etc/machine-id as the literal
      # "uninitialized", so systemd-machine-id-setup generates a NEW random id on
      # every boot. That churns everything seeded by the machine-id, notably
      # NetworkManager's stable cloned-MAC — and therefore the DHCP client-id and the
      # leased IP, so the host grabs a new address on every reboot. Persist it here
      # without commit's unmount: once systemd has put a valid transient id in place,
      # copy it into the persist root so the NEXT boot reads a stable id. Writing the
      # backing file directly (not through the bind/overmount) avoids the unmount that
      # broke commit. Idempotent — only fires while the persisted value is not yet a
      # 32-hex id, i.e. once on first boot, then never again.
      iteraPersistMachineId = mkIf (config.nix-mineral.enable && machineIdPersisted) ''
        persisted="${cfg.persistRoot}/etc/machine-id"
        current="$(cat /etc/machine-id 2>/dev/null || true)"
        stored="$(cat "$persisted" 2>/dev/null || true)"
        if [ "''${#current}" -eq 32 ] && [ "''${#stored}" -ne 32 ]; then
          printf '%s\n' "$current" > "$persisted"
        fi
      '';

      # Persist the mutable account databases so `passwd` (and any other mutable
      # account edits) survive the wiped root. /etc/shadow — where passwd writes
      # the new hash — otherwise regenerates from the declarative config on every
      # boot, so a changed password silently reverts.
      #
      # impermanence's own `files` mechanism can't do this: its persist-files
      # activation runs AFTER NixOS's `users` script has already created a
      # non-empty /etc/shadow, and impermanence's mount-file guard then refuses to
      # bind over a file that already exists. So bind these four DBs from the
      # persist root ourselves, BEFORE the `users` script runs (see the users.deps
      # below), and let that script read/write the persisted copies directly.
      #
      # First boot / first switch: seed the persisted copy from the live file if
      # one exists (preserving current passwords when this is first enabled),
      # otherwise start empty and let the `users` script populate it from the
      # declarative config (initialPassword/hashedPassword). Idempotent — the bind
      # mount is skipped once already mounted. `mountpoint`/`mount` come from the
      # activation PATH (util-linux).
      iteraPersistAccounts = mkIf cfg.accounts.enable (
        lib.stringAfter [ "etc" ] ''
          mkdir -p ${cfg.persistRoot}/etc
          for f in passwd group shadow gshadow; do
            src="${cfg.persistRoot}/etc/$f"
            if [ ! -s "$src" ] && [ -s "/etc/$f" ] && ! mountpoint -q "/etc/$f"; then
              cat "/etc/$f" > "$src"
            fi
            [ -e "$src" ] || : > "$src"
            touch "/etc/$f"
            mountpoint -q "/etc/$f" || mount --bind "$src" "/etc/$f"
          done
          chmod 0644 ${cfg.persistRoot}/etc/passwd ${cfg.persistRoot}/etc/group
          chmod 0600 ${cfg.persistRoot}/etc/shadow ${cfg.persistRoot}/etc/gshadow
        ''
      );

      # The users activation script (update-users-groups) must run AFTER the bind
      # mounts are in place, so its reads/writes of /etc/{passwd,group,shadow,
      # gshadow} land in the persisted copies rather than the tmpfs originals.
      users.deps = mkIf cfg.accounts.enable [ "iteraPersistAccounts" ];
    };
  };
}
