# itera's user-account battery.
#
# A thin convenience layer over NixOS `users.users` + hjem. Declaring
# `itera.users.<name>` creates the normal-user account AND turns on hjem home
# management for it, so the user automatically inherits every itera home battery
# (mango autostart, DankMaterialShell settings, keybinds, …) — that is how
# itera's "default settings for all users" reaches each user without any
# per-user fan-out here.
#
# Per-user HOME *overrides* are NOT declared here. They live on the hjem option
# path, e.g. `hjem.users.<name>.itera.programs.dankMaterialShell.settings` — the
# account layer only decides *who* the users are, the home batteries decide
# *what* is in their $HOME. This is the deliberate simplification over eiros,
# which crammed the whole home surface into its `users` submodule.
#
# Opt-out like the other core batteries: gated on the master `itera.enable`
# (so `itera.enable = false` drops all itera-declared users) with `mkDefault`
# values so every generated account field stays overridable. Declaring users
# the plain NixOS way (`users.users.<name>` + `hjem.users.<name>.enable`) keeps
# working unchanged and untouched by this module.
{
  config,
  lib,
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
in
{
  options.itera.users = mkOption {
    default = { };
    description = ''
      Declarative itera user accounts. Each entry creates a normal-user account
      and enables hjem home management for it (so the user gets itera's home
      batteries and their system-wide defaults). Override per-user home settings
      under {option}`hjem.users.<name>.itera.programs.*`.
    '';
    example = lib.literalExpression ''
      {
        itera.users.alice = {
          extraGroups = [ "wheel" "audio" "video" ];
          initialPassword = "changeme";
        };
      }
    '';
    type = attrsOf (
      submodule (
        { name, ... }:
        {
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
