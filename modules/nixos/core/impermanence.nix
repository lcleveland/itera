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
# `.local/share`, `.local/state`, `.cache`, `.ssh`, `Documents`, `Downloads`, plus
# `.steam` when Steam is on) is persisted by default so desktop/login state
# survives the wiped root with no per-user wiring. This reads the account set from
# `config.users.users` (filtered to normal users) — the same cross-battery
# introspection the module already does for secureBoot/flatpak/virtualisation —
# and merges those curated paths with any explicit `itera.impermanence.users.<name>`
# entries. Opt out via `homes.enable`. `Downloads` is persisted so large downloads
# land on disk instead of the size-capped tmpfs root, but its contents are emptied
# on every boot by default (`homes.clearDownloadsOnBoot`) so downloads don't
# accumulate across reboots; set that option to `false` to keep them.
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
  pkgs,
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
  inherit (lib) stringAfter;
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
  # Append Steam's bootstrap dir (~/.steam) when Steam is enabled. The library,
  # Proton prefixes (steamapps/compatdata), cloud saves (userdata) and the
  # login/credential cache (config/config.vdf) all live under ~/.local/share/Steam,
  # already persisted via `.local/share`. But ~/.steam is a top-level dotdir — none
  # of the curated home dirs — holding registry.vdf (auto-login user, language, UI
  # settings) plus the bin/root symlinks Steam rebuilds on launch; without it Steam
  # forgets the auto-login account and language every boot. Gated on
  # `programs.steam.enable`, the switch that actually creates the dir, so it covers
  # both the `itera.gaming` battery and a bare `programs.steam.enable`.
  homeDirectories = cfg.homes.directories ++ lib.optional config.programs.steam.enable ".steam";
  autoUsers = lib.mapAttrs (_: _: {
    directories = homeDirectories;
    inherit (cfg.homes) files;
  }) homeUsers;

  # Absolute ~/Downloads path for every normal user, used by the boot-time clear
  # service (itera.impermanence.homes.clearDownloadsOnBoot).
  downloadsDirs = map (u: "${u.home}/Downloads") (lib.attrValues homeUsers);
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

    passwords.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Persist mutable user passwords (`/etc/shadow`) across the wiped tmpfs
        root, so {command}`passwd` changes survive reboots. Without this,
        `/etc/shadow` regenerates from the declarative config every boot and
        password changes are silently lost.

        Implemented as a copy (never a bind mount / symlink): an activation
        script restores the persisted `/etc/shadow` before NixOS's `users` script
        runs, and a shutdown service copies it back — so NixOS's own atomic-rename
        writes to the file keep working. This requires mutable users
        (`users.mutableUsers = true`, the default); with `mutableUsers = false`
        the password is already declarative, so leave this off and use a
        `hashedPasswordFile` pointing into {option}`persistRoot`.
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
          # Claude Code's state dir: its OAuth credentials
          # (~/.claude/.credentials.json) plus settings/projects. Without this the
          # login is wiped every boot and you must re-authenticate.
          ".claude"
          "Documents"
          # Persisted so large downloads land on disk-backed /persist rather than
          # the size-capped tmpfs root. Its contents are emptied on every boot by
          # default (homes.clearDownloadsOnBoot); set that to false to keep them.
          "Downloads"
        ];
        description = "Home-relative directories persisted for each user when {option}`homes.enable` is set.";
      };

      files = mkOption {
        type = entryType;
        # Claude Code keeps account/onboarding/project-trust state in the home-root
        # ~/.claude.json (its credentials live in ~/.claude, persisted above). Keep
        # it so the CLI doesn't re-run first-run setup after every boot.
        default = [ ".claude.json" ];
        description = "Home-relative files persisted for each user when {option}`homes.enable` is set.";
      };

      clearDownloadsOnBoot = mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Empty every normal user's `~/Downloads` on each boot while keeping the
          folder itself on the disk-backed {option}`persistRoot`. On by default:
          large downloads still work (the folder is not on the size-capped tmpfs
          root), but its contents are wiped at boot so nothing accumulates across
          reboots. Set to `false` to instead keep downloads across reboots. Only
          meaningful while `Downloads` is persisted (the default via
          {option}`homes.directories`); otherwise the folder is on the tmpfs root
          and already empty each boot.
        '';
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
        # itera's power battery saves the last-active power-profiles-daemon profile
        # here (PPD itself does not persist it); without this the wiped root drops
        # the file and the profile resets to `balanced` every boot. Gated on the
        # same power-profiles-daemon switch the persist service is gated on.
        ++ lib.optional config.services.power-profiles-daemon.enable "/var/lib/itera-power-profile"
        # The DMS greeter's cache dir holds .local/state/memory.json — the last
        # successful username/session the greeter pre-selects. Persist it so the
        # greeter remembers the last user across the wiped tmpfs root. Gated on
        # the upstream greeter option, which is exactly what creates the dir (via
        # its own tmpfiles rule) and sets its greeter:greeter ownership.
        ++ lib.optional config.programs.dms-greeter.enable "/var/lib/dms-greeter"
        # ollama's model store and open-webui's DB/settings/users live under each
        # service's systemd StateDirectory. Both run as DynamicUser services, so the
        # real data sits at /var/lib/private/<name> (systemd recreates the
        # /var/lib/<name> symlink to it on each boot); persist the private backing
        # dirs so downloaded models and the web UI's accounts/settings/chats survive
        # the wiped root instead of filling tmpfs and vanishing every boot. Gated on
        # the upstream service switch — what actually creates the dir — so it covers
        # both the itera.ai battery and a bare services.<name>.enable.
        ++ lib.optional config.services.ollama.enable "/var/lib/private/ollama"
        ++ lib.optional config.services.open-webui.enable "/var/lib/private/open-webui"
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
    system.activationScripts = {
      # (See the long comment above the machine-id battery description.) Persist
      # the first-boot machine-id back to /persist without commit's unmount.
      iteraPersistMachineId = mkIf (config.nix-mineral.enable && machineIdPersisted) ''
        persisted="${cfg.persistRoot}/etc/machine-id"
        current="$(cat /etc/machine-id 2>/dev/null || true)"
        stored="$(cat "$persisted" 2>/dev/null || true)"
        if [ "''${#current}" -eq 32 ] && [ "''${#stored}" -ne 32 ]; then
          printf '%s\n' "$current" > "$persisted"
        fi
      '';

      # Persist mutable passwords (/etc/shadow) by COPY, never a bind mount or
      # symlink. NixOS's `users` script writes /etc/shadow with an atomic rename
      # (write-temp + rename over the target); a rename onto a bind-mount point or
      # a symlink fails / gets replaced, which either aborts activation (EBUSY —
      # the mass "Unknown user/group" boot failure) or silently reverts the change
      # on reboot. Copies avoid both: the users script always writes a plain
      # tmpfs file.
      #
      # Runs BEFORE the `users` script (see users.deps below):
      #   1. Save the live /etc/shadow first — on a `nixos-rebuild switch` it holds
      #      any interactive `passwd` change not yet flushed to /persist, so this
      #      captures it before step 2 could overwrite it.
      #   2. Restore the persisted /etc/shadow so the (mutable) users script keeps
      #      those hashes instead of resetting them to initialPassword.
      # Both guarded on a non-empty (-s) source so an empty file can never clobber
      # good data. First ever boot: neither exists yet, both steps skip, and the
      # users script seeds /etc/shadow from initialPassword/hashedPassword — which
      # the shutdown service below then persists.
      iteraPersistShadow = mkIf cfg.passwords.enable (
        stringAfter [ "etc" ] ''
          persisted="${cfg.persistRoot}/etc/shadow"
          mkdir -p "$(dirname "$persisted")"
          [ -s /etc/shadow ] && cp -f /etc/shadow "$persisted"
          [ -s "$persisted" ] && cp -f "$persisted" /etc/shadow
          [ -e "$persisted" ] && chmod 0600 "$persisted"
        ''
      );

      # The users activation script (update-users-groups) must run AFTER the
      # restore so it merges the persisted hashes.
      users.deps = mkIf cfg.passwords.enable [ "iteraPersistShadow" ];
    };

    systemd.services = {
      # Capture interactive `passwd` changes: copy /etc/shadow to /persist on
      # shutdown. Paired with the restore-before-`users` activation step above,
      # this is what makes a `passwd` change survive a reboot with no rebuild in
      # between. Only unclean shutdowns (power loss) between the change and
      # shutdown are lost.
      itera-persist-shadow = mkIf cfg.passwords.enable {
        description = "Persist /etc/shadow across the ephemeral root";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecStop = pkgs.writeShellScript "itera-persist-shadow" ''
            mkdir -p "${cfg.persistRoot}/etc"
            [ -s /etc/shadow ] && cp -f /etc/shadow "${cfg.persistRoot}/etc/shadow"
            [ -e "${cfg.persistRoot}/etc/shadow" ] && chmod 0600 "${cfg.persistRoot}/etc/shadow"
          '';
        };
      };

      # Opt-out to persisting downloads across reboots: keep ~/Downloads on the
      # disk-backed /persist (so it isn't size-capped by the tmpfs root) but empty
      # its contents on every boot. `RequiresMountsFor` the Downloads paths so
      # systemd orders this AFTER impermanence's bind mounts are in place —
      # otherwise it could empty an as-yet-unmounted tmpfs dir and leave the
      # persisted contents untouched. Runs before multi-user.target so the folder
      # is clean before any login/desktop session starts. `-mindepth 1` empties
      # the contents while leaving the directory (and its ownership) intact.
      itera-clear-downloads = mkIf cfg.homes.clearDownloadsOnBoot {
        description = "Empty persisted ~/Downloads on each boot";
        wantedBy = [ "multi-user.target" ];
        unitConfig.RequiresMountsFor = downloadsDirs;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "itera-clear-downloads" ''
            for dir in ${lib.escapeShellArgs downloadsDirs}; do
              [ -d "$dir" ] && ${pkgs.findutils}/bin/find "$dir" -mindepth 1 -delete
            done
          '';
        };
      };
    };
  };
}
