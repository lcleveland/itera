# Evaluation check for the update battery (modules/nixos/core/update.nix).
#
# The battery records this host's update source — which flake `itera
# rebuild`/`update` build from and which nixosConfiguration attribute this host
# is — to /etc/itera/update.env, and feeds `programs.nh.flake` (NH_FLAKE). What
# matters is the wiring: a flake sets NH_FLAKE; remote-vs-local is classified
# correctly (it drives --refresh vs --update in cli/itera.sh); the configuration
# defaults to the hostname; and the renamed `itera.nix.nh.flake` still works.
# `nix build` forces evaluation and fails loudly on any false assertion.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;

  inherit (lib.strings) hasInfix;

  envText = c: c.environment.etc."itera/update.env".text;

  # No source configured: flake unset, configuration defaults to the hostname.
  base = mkConfig [ ];

  # Remote flake ref (updated with --refresh).
  remote = mkConfig [ { itera.update.flake = "github:me/dream"; } ];

  # Local checkout path (updated with --update).
  local = mkConfig [ { itera.update.flake = "/home/alice/config"; } ];

  # The renamed option: `itera.nix.nh.flake` must still land on the new one.
  renamed = mkConfig [ { itera.nix.nh.flake = "/home/alice/config"; } ];

  # A host whose hostname is the configuration attribute it rebuilds.
  named = mkConfig [ { itera.networking.hostName = "dream"; } ];

  # An explicit configuration overriding the hostname default.
  customCfg = mkConfig [ { itera.update.configuration = "workstation"; } ];

  # Battery off: no NH_FLAKE even with a flake set.
  off = mkConfig [
    {
      itera.update.enable = false;
      itera.update.flake = "github:me/dream";
    }
  ];

  checks = {
    # --- defaults ---
    "flake is unset by default (NH_FLAKE left to nh's own default)" = base.programs.nh.flake == null;
    "configuration defaults to the system hostname" = base.itera.update.configuration == "itera";
    "env file records the default configuration" = hasInfix "ITERA_UPDATE_CONFIGURATION=itera" (
      envText base
    );
    "env file omits a flake when none is set" = !hasInfix "ITERA_UPDATE_FLAKE=" (envText base);

    # --- remote flake ref ---
    "a flake sets programs.nh.flake so NH_FLAKE points at the config" =
      remote.programs.nh.flake == "github:me/dream";
    "env file records the flake" = hasInfix "ITERA_UPDATE_FLAKE=github:me/dream" (envText remote);
    "a remote flake ref is classified remote (drives --refresh)" = hasInfix "ITERA_UPDATE_REMOTE=1" (
      envText remote
    );

    # --- local checkout path ---
    "a local path sets programs.nh.flake" = local.programs.nh.flake == "/home/alice/config";
    "a local path is classified local (drives --update)" = hasInfix "ITERA_UPDATE_REMOTE=0" (
      envText local
    );

    # --- renamed option (itera.nix.nh.flake -> itera.update.flake) ---
    "the renamed itera.nix.nh.flake still sets programs.nh.flake" =
      renamed.programs.nh.flake == "/home/alice/config";
    "the renamed option flows into the env file" = hasInfix "ITERA_UPDATE_FLAKE=/home/alice/config" (
      envText renamed
    );

    # --- configuration name ---
    "configuration follows the hostname" = named.itera.update.configuration == "dream";
    "env file records the hostname-derived configuration" =
      hasInfix "ITERA_UPDATE_CONFIGURATION=dream" (envText named);
    "an explicit configuration overrides the hostname default" =
      hasInfix "ITERA_UPDATE_CONFIGURATION=workstation" (envText customCfg);

    # --- battery off ---
    "the battery off leaves NH_FLAKE unset even with a flake set" = off.programs.nh.flake == null;
  };

in
mkCheckDrv "itera-update-eval" checks
