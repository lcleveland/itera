# itera's user-account battery.
#
# A thin convenience layer over NixOS `users.users` + hjem. Declaring
# `itera.users.<name>` creates the normal-user account AND turns on hjem home
# management for it, so the user automatically inherits every itera home battery
# (mango autostart, DankMaterialShell settings, keybinds, …) — that is how
# itera's "default settings for all users" reaches each user without any
# per-user fan-out here.
#
# Per-user HOME *overrides* live under `itera.users.<name>.programs.<app>.*` —
# the curated-program framework (lib/programs.nix) splices each program's per-user
# option set into this submodule via `imports` below. Setting one overrides the
# system-wide default (`itera.programs.<app>.*`) per key; the matching hjem battery
# reads the merged result via `osConfig` and renders it into the user's $HOME. The
# account layer still only decides *who* the users are and their account fields;
# the `programs.<app>` leaves are contributed by the desktop/program registrations,
# so this module stays app-agnostic.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# (so `itera.enable = false` drops all itera-declared users) with `mkDefault`
# values so every generated account field stays overridable. Declaring users
# the plain NixOS way (`users.users.<name>` + `hjem.users.<name>.enable`) keeps
# working unchanged and untouched by this module.
{
  config,
  lib,
  iteraLib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    attrsOf
    submodule
    listOf
    str
    bool
    ;

  cfg = config.itera.users;

  # Per-user curated-program option fragments, spliced into the account submodule
  # so each user gets `programs.<app>.*` overrides for every registered program.
  programRegistrations = import ../../programs { inherit lib iteraLib; };
in
{
  options.itera.users = mkOption {
    default = { };
    description = ''
      Declarative itera user accounts. Each entry creates a normal-user account
      and enables hjem home management for it (so the user gets itera's home
      batteries and their system-wide defaults). Set per-user curated-program
      overrides under {option}`itera.users.<name>.programs.<app>.*` (each wins per
      key over the system-wide default {option}`itera.programs.<app>.*`).
    '';
    example = lib.literalExpression ''
      {
        itera.users.alice = {
          extraGroups = [ "wheel" "audio" "video" ];
          initialPassword = "changeme";
          programs.mango.layout = "tile";
          programs.dankMaterialShell.settings.cornerRadius = 8;
        };
      }
    '';
    type = attrsOf (
      submodule (
        { name, ... }:
        {
          # Curated-program per-user option leaves (`programs.<app>.*`).
          imports = map (r: r.usersSubmodule) programRegistrations;

          options = {
            isNormalUser = mkOption {
              type = bool;
              default = true;
              description = "Create the account as a normal (human) user.";
            };

            extraGroups = mkOption {
              type = listOf str;
              default = [
                "wheel"
                "networkmanager"
                "video"
                "audio"
              ];
              example = [
                "wheel"
                "libvirtd"
              ];
              description = "Supplementary groups for the user.";
            };

            initialPassword = mkOption {
              type = str;
              default = name;
              description = ''
                Initial password set at account creation. WARNING: defaults to
                the username — change it before deploying a real system (prefer
                `hashedPassword` / `hashedPasswordFile` set directly on
                {option}`users.users.<name>`, which merges with this).
              '';
            };

            description = mkOption {
              type = str;
              default = name;
              description = "GECOS description / display name for the account.";
            };

            enableHome = mkOption {
              type = bool;
              default = true;
              description = "Enable hjem home management (and thus itera's home batteries) for this user.";
            };
          };
        }
      )
    );
  };

  config = mkIf config.itera.enable {
    # Make declarative home files always win on rebuild. hjem's linker (smfh)
    # only overwrites an existing target path when the file's `clobber` is set,
    # and that defaults to `hjem.clobberByDefault` = false. Under itera's
    # default-on impermanence the root is wiped every boot and each persisted
    # home dir (~/.config, …) is restored from /persist, so a clobber-false file
    # is seen as already-present and the linker refuses to replace it — freezing
    # it at whatever store path it FIRST linked, forever ignoring later config
    # changes (this is what stranded ~/.config/mango/config.conf on the old
    # `spawn,ghostty` bind long after the generation had switched to WezTerm).
    # Turning the default on means every itera-managed home file tracks the
    # active generation. A file that must survive out-of-band edits (e.g. a GUI
    # writing its own config) still opts out with an explicit `clobber = false`,
    # as the DankMaterialShell battery exposes.
    hjem.clobberByDefault = mkDefault true;

    warnings = lib.flatten (
      lib.mapAttrsToList (
        username: user:
        lib.optional (user.initialPassword == username)
          "itera.users.${username}: initialPassword equals the username — change it before deploying to a real system."
      ) cfg
    );

    # Create every account. Fields are mkDefault so a plain `users.users.<name>`
    # block can still refine them (e.g. set a real hashedPassword).
    users.users = lib.mapAttrs (_: user: {
      isNormalUser = mkDefault user.isNormalUser;
      extraGroups = mkDefault user.extraGroups;
      initialPassword = mkDefault user.initialPassword;
      description = mkDefault user.description;
    }) cfg;

    # Enable hjem for each user (unless enableHome is false). `user`/`directory`
    # are intentionally NOT set here — hjem defaults them from the matching
    # users.users.<name> entry we create above. Every hjem.users.<name> keyed
    # here has a users.users.<name>, which hjem requires.
    hjem.users = lib.mapAttrs (_: user: {
      enable = mkDefault user.enableHome;
    }) cfg;
  };
}
