# itera's DankMaterialShell (DMS) battery.
#
# A thin, opinionated wrapper over two bundled NixOS modules (see
# `modules/nixos/default.nix`): DMS's shell (`programs.dank-material-shell`) and
# the standalone dank-greeter greeter (`programs.dms-greeter`) that DMS's greeter
# was extracted into upstream. DMS is a Quickshell-based Wayland desktop shell;
# this battery stands up a complete, login-to-desktop experience on top of the
# mango compositor.
#
# It pulls in the mango battery (`itera.desktop.mango`) — the shell is useless
# without a compositor — and, unless you opt out, turns on the dank-greeter greetd
# greeter rendered under mango. Login lands in the `mango` session, whose
# user-side autostart (`itera.programs.mango`, the hjem battery) launches `dms`.
#
# Opt-OUT: on automatically with `itera.enable` (following the same shape as
# `itera.hardening`), gated on `itera.enable && cfg.enable` with `mkDefault`
# values so it comes along by default but every knob is overridable. Set
# `itera.desktop.dankMaterialShell.enable = false` to drop the desktop while
# keeping the rest of itera. DMS's feature toggles (`enableSystemMonitoring`,
# `enableDynamicTheming`, …) keep their upstream defaults and stay reachable
# through the native `programs.dank-material-shell.*` options, since the upstream
# module is bundled.
#
# Greeter wiring note: the dank-greeter module enables greetd, which (via the
# nixpkgs greetd module) already creates the `greeter` system user and defaults
# `services.greetd.settings.default_session.user` to `"greeter"` — so we do not
# declare that user here.
#
# Scope: this module owns *installation* and the greeter/session wiring. The
# curated DMS *settings* are declared once by the curated-program registration
# `modules/programs/dankmaterialshell.nix`, exposed system-wide at
# `itera.programs.dankMaterialShell.*` and per-user at
# `itera.users.<name>.programs.dankMaterialShell.*`; the hjem battery
# `modules/hjem/programs/dankmaterialshell.nix` renders the merged result.
{
  config,
  lib,
  pkgs,
  iteraLib,
  iteraInputs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types)
    bool
    nullOr
    path
    str
    ;

  cfg = config.itera.desktop.dankMaterialShell;

  # The settings schema version of the bundled DMS, read from its source (no
  # IFD) so itera's settings never trigger a migration DMS cannot save back.
  dmsConfigVersion = lib.toInt (
    builtins.head (
      builtins.match ".*settingsConfigVersion: ([0-9]+).*" (
        lib.findFirst (lib.hasInfix "property int settingsConfigVersion:")
          (throw "itera: DMS settingsConfigVersion not found")
          (lib.splitString "\n" (builtins.readFile "${iteraInputs.dms}/quickshell/Common/SettingsData.qml"))
      )
    )
  );

  # itera's DMS settings for one user, merged exactly as the hjem renderer does.
  userSettings =
    name:
    (config.itera.programs.dankMaterialShell.settings or { })
    // (config.itera.users.${name}.programs.dankMaterialShell.settings or { });

  # What the greeter is seeded with (docs/look.md#greeter): with no sync user,
  # SYSTEM tokens (palette, the greeter image, and the start mode, so auto
  # shows dark); with one, that user's look over their mirrored DMS files.
  sync = cfg.greeter.syncUser;
  greeterLook = iteraLib.look.resolve config sync;
  greeterTheme = iteraLib.look.dmsTheme greeterLook;
  greeterSeed = {
    theme = greeterTheme;
    settings =
      iteraLib.look.dmsSettings greeterLook "${pkgs.writeText "itera-dms-greeter-theme.json" (
        builtins.toJSON greeterTheme
      )}"
      // (
        if sync != null then
          userSettings sync
        else
          {
            # The greeter prefers `lockScreenWallpaperPath` over the session
            # wallpaper; set only in the greeter's copy.
            lockScreenWallpaperPath = "${iteraLib.brand.greeterPng pkgs greeterLook.startColors}";
          }
          // config.itera.programs.dankMaterialShell.settings
      )
      // lib.optionalAttrs (cfg.greeter.wallpaper != null) {
        lockScreenWallpaperPath = "${cfg.greeter.wallpaper}";
      };
    # The mode lives in session.json; a synced user's copy carries their own.
    session = if sync != null then null else { isLightMode = greeterLook.startMode == "light"; };
  };
in
{
  options.itera.desktop.dankMaterialShell = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Install the DankMaterialShell desktop (on the mango compositor). On by
        default whenever {option}`itera.enable` is set; set this to `false` to opt
        out of the desktop while keeping the rest of itera.
      '';
    };

    greeter = {
      enable = mkOption {
        type = bool;
        default = true;
        description = ''
          Use the dank-greeter greetd greeter (rendered under mango) as the login
          manager — the DankMaterialShell-styled greeter, split into its own upstream
          project. On by default whenever the desktop is enabled; set this to `false`
          to install the shell without a display manager (you then arrange login
          yourself).
        '';
      };

      syncUser = mkOption {
        type = nullOr str;
        default = null;
        example = "alice";
        description = ''
          User whose whole DankMaterialShell look the greeter mirrors at each
          greetd start: their theme, mode, wallpaper and settings (DMS GUI changes
          plus itera's settings and look for that user), as DMS does upstream.
          `null` (default) gives the greeter the system look: system palette and
          mode (`auto` shows dark) and the itera greeter image. Per-user look
          overrides don't reach it.
        '';
      };

      wallpaper = mkOption {
        type = nullOr path;
        default = null;
        example = lib.literalExpression "./login-background.jpg";
        description = ''
          Wallpaper for the login screen only, independent of any desktop and
          lock-screen wallpaper. `null` (default) shows the itera greeter image,
          or follows the synced user. A path inside your configuration is copied
          to the Nix store; an absolute path outside it must be readable by the
          `greeter` user.
        '';
      };

      seed = mkOption {
        type = lib.types.attrsOf lib.types.anything;
        internal = true;
        readOnly = true;
        default = greeterSeed;
        description = "The theme, settings and session the greeter is seeded with.";
      };
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) (mkMerge [
    {
      itera = {
        # The shell needs a compositor — pull mango in.
        desktop.mango.enable = mkDefault true;

        programs.dankMaterialShell = {
          # Pin the schema version DMS expects (see `dmsConfigVersion`).
          settings.configVersion = mkDefault dmsConfigVersion;

          # IP Indicator: a default-on DMS dank-bar widget (public IP / ISP /
          # location). `enable` defaults to true in the plugins submodule, so this
          # alone ships it on; `mkDefault` lets a consumer re-pin `src` or drop it.
          # Per-user opt-out:
          #   itera.users.<name>.programs.dankMaterialShell.plugins.ipIndicator.enable = false;
          # Tracked as the `dms-ipindicator` flake input (source-only), so bumping
          # it is `nix flake update dms-ipindicator` — no rev/hash in this file.
          plugins.ipIndicator.src = mkDefault iteraInputs.dms-ipindicator;

          # Layout chooser: a `#layout` launcher plugin (SUPER+CTRL+n) that sets
          # the focused tag's mango layout by name. The attribute name must match
          # plugin.json's `id`. Lists every layout rather than `layoutCycle`, which
          # only governs SUPER+SHIFT+n.
          plugins.layoutChooser = mkIf config.itera.desktop.mango.enable {
            src = mkDefault ../../../pkgs/dms-layout-chooser;
            settings = mkDefault {
              layouts = iteraLib.mango.supportedLayouts;
              mmsg = lib.getExe' config.programs.mango.package "mmsg";
            };
          };

          # Enabling a plugin only REGISTERS it — a dank-bar widget renders only
          # when its id appears in a bar config's widget list. itera's keys
          # live in the read-only config.d/00-itera.json drop-in, which wins over
          # DMS's own settings.json (a GUI edit to one lasts until DMS restarts),
          # so the bar layout must be declared here too. Ship
          # DMS's default bar (schema matches the pinned `configVersion`) with
          # `ipIndicator` and `iteraUpdate` (the update-indicator battery,
          # modules/nixos/desktop/update-indicator.nix) added to the right
          # widgets. mkDefault so a consumer replaces the whole bar via
          # `itera.programs.dankMaterialShell.settings.barConfigs`. (Disabling the
          # plugin leaves a harmless dangling id here — DMS finds no component and
          # skips it.)
          settings.barConfigs = mkDefault [
            {
              id = "default";
              name = "Main Bar";
              enabled = true;
              position = 0;
              screenPreferences = [ "all" ];
              showOnLastDisplay = true;
              leftWidgets = [
                "launcherButton"
                "workspaceSwitcher"
                # DMS's built-in mango layout indicator; click to pick a layout.
                "layout"
                "focusedWindow"
              ];
              centerWidgets = [
                "music"
                "clock"
                "weather"
              ];
              rightWidgets = [
                "systemTray"
                "privacyIndicator"
                "idleInhibitor"
                "clipboard"
                "cpuUsage"
                "memUsage"
                "ipIndicator"
                "iteraUpdate"
                "notificationButton"
                "battery"
                "controlCenterButton"
              ];
            }
          ];
        };
      };

      programs.dank-material-shell = {
        enable = mkDefault true;

        # Run the shell as a systemd user service bound to the mango session
        # instead of a mango `exec_once`, so a crash restarts it rather than
        # leaving the session without a bar, launcher or lock screen. The hjem
        # mango battery drops its `exec_once` when this is on. No restart on
        # rebuild: a fresh shell starts with an empty tray, and tray clients
        # (udiskie, netskope's stagentui, …) don't all re-register.
        systemd = {
          enable = mkDefault true;
          target = mkDefault "mango-session.target";
          restartIfChanged = mkDefault false;
        };
      };

      systemd.user.services.dms = mkIf config.programs.dank-material-shell.systemd.enable {
        # The greeter's mango starts mango-session.target too; keep the shell out
        # of system users' sessions (same guard as the clipboard bridges).
        unitConfig.ConditionUser = "!@system";
        # Apps started from the launcher would otherwise live in dms.service's
        # cgroup and die whenever the shell is restarted. A scope per launch
        # moves them out. DMS reads this when `launchPrefix` is unset.
        environment.DMS_DEFAULT_LAUNCH_PREFIX = "systemd-run --user --scope --collect --quiet";
      };

      # The lock screen's PAM service.
      #
      # DMS authenticates its lock screen against `/etc/pam.d/dankshell` whenever
      # that service exists. When it does NOT, DMS falls back to generating a
      # stack imperatively at every shell start — `dms auth resolve-lock`, which
      # flattens `/etc/pam.d/login` into `~/.local/state/DankMaterialShell/pam/`
      # ("used by the shell as a fallback when /etc/pam.d/dankshell is not
      # managed", per its own `--help`). Declaring the service here claims that
      # surface: the stack lands in the closure, is covered by the eval checks,
      # and — since itera persists `~/.local/state` — stops a generated file full
      # of hardcoded store paths from outliving the generation that produced it,
      # which would leave the lock screen unable to load `pam_unix.so` at all.
      #
      # Deliberately NOT derived from `login`: an unlock is not a login, so this
      # stack authenticates and nothing else. nixpkgs defaults `startSession`
      # (and `setLoginUid` with it) to false, so no pam_systemd/pam_loginuid
      # registers a second session and no pam_securetty vets a tty that isn't
      # there — all of which the flattened-`login` fallback dragged along.
      #
      # Fingerprint and security key stay OFF here even though both batteries are
      # on by default, because nixpkgs would otherwise inherit them from
      # `services.fprintd.enable` / `security.pam.u2f.enable`. DMS drives those
      # two factors through its OWN PAM contexts (the `fprint` and `u2f` stacks
      # bundled inside the package), so a second copy inline here would
      # double-prompt — `dms auth validate` flags precisely that ("pam_fprintd is
      # present in the resolved stack; may double-prompt with DMS's separate
      # fingerprint context"). The factors reach the lock screen through DMS's
      # `enableFprint`/`enableU2f` settings instead; see the fingerprint and
      # security-keys batteries. Keyring unlock is wired the other way round, by
      # `itera.keyring.pamServices`, which lists this service.
      security.pam.services.dankshell = {
        fprintAuth = mkDefault false;
        u2f.enable = mkDefault false;
      };

      # The IP Indicator widget shells out to `curl`, which itera does not
      # otherwise install.
      environment.systemPackages = [ pkgs.curl ];

      # DMS turns on geoclue (`services.geoclue2.enable`) for its location-aware
      # features. geoclue's network backend reaches for avahi, which itera
      # otherwise leaves off — so every boot it logs "Failed to connect to avahi
      # service: Daemon not running". Enable avahi to satisfy the dependency
      # (and get `.local`/mDNS resolution as a bonus). mkDefault so a host that
      # would rather drop location can instead set `services.geoclue2.enable`
      # (or this) to false. Note: this runs an mDNS responder — acceptable for a
      # desktop, but flip off if you want zero LAN broadcast on a hardened box.
      # nssmdns4/6 register the mDNS NSS module so glibc actually resolves
      # `.local` names — without them avahi runs but logs "No NSS support for
      # mDNS detected, consider installing nss-mdns!" and nothing can resolve the
      # responder it advertises. Delivers the `.local` resolution promised above.
      services.avahi = {
        enable = mkDefault true;
        nssmdns4 = mkDefault true;
        nssmdns6 = mkDefault true;
      };

      # …and give that geoclue an IP source. nixpkgs' `services.geoclue2` module
      # generates /etc/geoclue/geoclue.conf from scratch and emits no `[ip]`
      # section at all — no `enable`, no `method` — so geoclue reads a null method,
      # logs `Unknown IP source method '(null)', disabling source`, and drops IP
      # geolocation for the whole session. There is no module option for it, so
      # append the section: `environment.etc.<name>.text` is `types.lines`, which
      # merges by concatenation, and INI sections are order-independent — so
      # `mkAfter` adds a section without re-deriving upstream's generator.
      #
      # `method=ichnaea` re-instates upstream geoclue's OWN default (see the
      # `[ip]` block in the package's stock geoclue.conf) and reuses the Ichnaea
      # URL from the wifi source, i.e. the api.beacondb.net endpoint the
      # already-enabled wifi source queries — so this adds a location source, not
      # a network peer. It matters on the machines least able to do without it:
      # with no wifi hardware the wifi source can never get a fix, leaving DMS
      # auto-location (weather, night-light) permanently unresolved.
      #
      # `enable=false` here silences the warning just as well if you would rather
      # have no IP geolocation — geoclue checks `enable` before parsing `method`,
      # so it short-circuits before the null. That is the knob to flip; overriding
      # this whole entry is not required.
      environment.etc."geoclue/geoclue.conf".text = mkIf config.services.geoclue2.enable (
        lib.mkAfter ''

          [ip]
          enable=true
          method=ichnaea
        ''
      );
    }

    {
      # Tell the `dms` CLI the system is immutable: block the subcommands that
      # rewrite files NixOS owns (`dms setup` replaces the mango config and moves
      # binds into dms/; the greeter installers edit greetd and PAM in /etc).
      # Same list as upstream's packaged policy for image-based distros.
      environment.etc."dms/cli-policy.json".text = builtins.toJSON {
        policy_version = 1;
        immutable_system = true;
        blocked_commands = [
          "setup"
          "greeter install"
          "greeter enable"
          "greeter uninstall"
        ];
        message = "This system is managed declaratively by itera (NixOS); change it in your configuration instead.";
      };

      # External-monitor brightness: DMS drives DDC/CI over /dev/i2c-*, which
      # needs the i2c-dev module and the `i2c` group for every desktop user.
      hardware.i2c.enable = mkDefault true;
      # Membership via the group, not users.users.<n>.extraGroups, which would
      # replace the itera users' mkDefault group list instead of adding to it.
      users.groups.${config.hardware.i2c.group}.members = mkIf config.hardware.i2c.enable (
        lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.itera.users)
      );
    }

    {
      # Qt (DMS lane, docs/look.md#delivery-lanes): DMS always renders its
      # KColorScheme (~/.local/share/color-schemes/DankMatugen.colors), and when
      # QT_QPA_PLATFORMTHEME is qtengine it points qtengine's config at it, so
      # Qt 6 apps repaint live. The variable reaches dms.service through PAM.
      # Until DMS first runs, qtengine finds no config and uses its defaults.
      # `qt.enable` puts the system profile's Qt plugin dirs on QT_PLUGIN_PATH.
      qt.enable = mkDefault true;
      environment = {
        sessionVariables.QT_QPA_PLATFORMTHEME = mkDefault "qtengine";
        systemPackages = [ pkgs.qtengine ];
      };
    }

    (mkIf cfg.greeter.enable {
      programs.dms-greeter = {
        enable = mkDefault true;
        # `compositor.name` has no upstream default; render the greeter under mango.
        compositor.name = mkDefault "mango";
        # Give the greeter's mango instance the same monitor layout AND keyboard
        # layout as the session so the login screen comes up with the right
        # resolution/position on multi-monitor setups and accepts the configured
        # XKB layout at the password prompt. The greeter is pre-login and
        # single-instance, so it takes the SYSTEM-WIDE monitors
        # (`itera.programs.mango.monitors`) and the system XKB config
        # (`itera.keyboard` via `services.xserver.xkb`) — the per-user layer does
        # not apply here. `customConfig` (type lines) is passed to mango via `-C`;
        # empty when nothing is set, leaving mango to auto-configure exactly as before.
        compositor.customConfig = mkDefault (
          lib.concatStringsSep "\n" (
            lib.filter (line: line != "") [
              (iteraLib.mango.renderMonitorRules config.itera.programs.mango.monitors)
              (iteraLib.mango.renderXkb {
                inherit (config.services.xserver.xkb) layout variant options;
              })
            ]
          )
        );
        # Theme sync: greetd's preStart copies this user's DMS settings.json,
        # session.json (wallpapers) and dms-colors.json (dynamic theme) into
        # the greeter's cache at every start. itera's own keys live in a
        # config.d drop-in the module does not copy; they are merged in below.
        # Opt-in: with no sync user the greeter shows the system look.
        configHome = mkIf (cfg.greeter.syncUser != null) (
          mkDefault config.users.users.${cfg.greeter.syncUser}.home
        );
      };

      # Parse the greeter's mango config at build time, like the per-user one
      # (see `validateConfig` in lib/mango.nix).
      system.checks =
        lib.optional
          (
            config.programs.dms-greeter.compositor.name == "mango"
            && config.programs.dms-greeter.compositor.customConfig != ""
          )
          (
            iteraLib.mango.validateConfig {
              inherit pkgs;
              name = "dms-greeter-mango-config";
              mango = config.programs.mango.package;
              text = config.programs.dms-greeter.compositor.customConfig + "\n";
            }
          );

      # The mango session the mango module registers. The greeter's own session
      # picker ignores this (it offers the last-used session, else the first one
      # found); it is what autologin and other display managers fall back on.
      services.displayManager.defaultSession = mkDefault "mango";

      # The nixpkgs greetd module runs the greeter as the `greeter` user with
      # home `/var/empty` (read-only). The greeter session (mango + Quickshell)
      # starts wireplumber, and the greetd PAM stack starts gnome-keyring — both
      # write under $HOME and fail every boot ("failed to create directory
      # /var/empty/.local/state/wireplumber", "unable to create keyring dir").
      # Point the greeter at a writable, ephemeral home on tmpfs: a greeter keeps
      # no state, so /run (wiped each boot) is the right place and needs no
      # impermanence persistence.
      users.users.greeter.home = lib.mkForce "/run/greeter-home";
      systemd.tmpfiles.settings."10-itera-greeter"."/run/greeter-home".d = {
        user = "greeter";
        group = "greeter";
        mode = "0700";
      };

      # Survive the GPU/DRM startup race. greetd has no ordering dependency on
      # the DRM device, so on some boots the mango greeter starts before
      # /dev/dri/cardN exists, logs "Found 0 GPUs, cannot create backend", and
      # exits. greetd restarts on that (Restart=on-success) — but the upstream
      # cadence (RestartSec≈100ms, StartLimitBurst=5 over 10s) burns all five
      # retries in ~0.5s, well before a device that appears a couple seconds
      # later, leaving the login manager permanently dead (`start-limit-hit`,
      # system `degraded`) until a manual restart. Space retries out and never
      # give up permanently, so the greeter simply reappears once the GPU is
      # ready. RestartSec also gates the normal post-logout restart, so keep it
      # short.
      systemd.services.greetd = {
        serviceConfig.RestartSec = mkDefault "1s";
        startLimitIntervalSec = mkDefault 0;

        preStart =
          let
            dir = "/var/lib/dms-greeter";
            user = config.services.greetd.settings.default_session.user;
            iteraSettings = pkgs.writeText "itera-dms-greeter-settings.json" (
              builtins.toJSON greeterSeed.settings
            );
          in
          mkMerge [
            # The cache is persisted and the module's copy only adds files, so a
            # source that went away (sync user removed, file deleted) would leave
            # its last copy behind forever. Start from a clean slate each time.
            (lib.mkBefore ''
              rm -f ${dir}/settings.json ${dir}/settings.orig.json ${dir}/session.json \
                ${dir}/dms-colors.json ${dir}/colors.json
            '')
            # itera's keys win over the synced settings.json, as they do in the
            # session (config.d layers over settings.json). Shallow merge, matching
            # DMS's per-key layering.
            (lib.mkAfter ''
              if [ -f ${dir}/settings.json ]; then
                ${lib.getExe pkgs.jq} -s '.[0] + .[1]' ${dir}/settings.json ${iteraSettings} > ${dir}/settings.tmp
                mv ${dir}/settings.tmp ${dir}/settings.json
              else
                cp ${iteraSettings} ${dir}/settings.json
              fi
              chmod 0640 ${dir}/settings.json
              chown ${user}: ${dir}/settings.json
            '')
            # No sync user: the system mode, which only session.json carries.
            (lib.mkIf (greeterSeed.session != null) (
              lib.mkAfter ''
                cp ${pkgs.writeText "itera-dms-greeter-session.json" (builtins.toJSON greeterSeed.session)} ${dir}/session.json
                chmod 0640 ${dir}/session.json
                chown ${user}: ${dir}/session.json
              ''
            ))
          ];
      };
    })
  ]);
}
