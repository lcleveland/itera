# itera's update battery: where `itera rebuild`/`update` build from, and which
# configuration this host is.
#
# The `itera` command's rebuild/update verbs (cli/itera.sh) are thin `nh os
# switch` wrappers. Two things they need are properties of the *installed* host,
# not of any single invocation, so a consumer sets them once in their config and
# every later `itera update`/`rebuild` just works with no arguments:
#
#   itera.update.flake          the flake ref/URL to build from — a remote URL
#                               (github:me/dream) or a local checkout path.
#   itera.update.configuration  which nixosConfiguration attribute is THIS host,
#                               so a box built as `dream` rebuilds `#dream`.
#
# This module records the effective values to /etc/itera/update.env (mirroring
# the facter battery's /etc/itera/facter.env), and cli/itera.sh reads them to
# assemble the `nh` command line. `flake` also feeds `programs.nh.flake`
# (NH_FLAKE) so a bare `nh os switch` outside the `itera` command resolves too.
#
# Remote vs local is decided HERE, in Nix, and published as ITERA_UPDATE_REMOTE
# so the shell stays dumb: `itera update` uses `--refresh` (fetch the newest
# revision) for a remote ref and `--update` (bump the local flake.lock) for a
# path. A value starting with `/` or `.` is a filesystem path (local);
# everything else (github:, git+…, https:, flake:, …) is remote.
#
# Opt-out shape like the other core batteries: gated on the master
# `itera.enable` with a per-feature `enable` (default true); values set with
# `mkDefault` so a consumer can override.
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.strings) hasPrefix optionalString;
  inherit (lib.types) bool nullOr str;

  cfg = config.itera.update;

  # A filesystem path (local checkout) starts with `/` or `.`; any other form is
  # a remote flake reference. `null` is neither — the env line is omitted.
  isLocal = f: hasPrefix "/" f || hasPrefix "." f;
in
{
  # Old home of the flake option; keep consumer configs (and the template's
  # commented example) working with a rename warning.
  imports = [
    (lib.mkRenamedOptionModule [ "itera" "nix" "nh" "flake" ] [ "itera" "update" "flake" ])
  ];

  options.itera.update = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Publish this host's update settings ({option}`itera.update.flake` and
        {option}`itera.update.configuration`) for the `itera` command's
        rebuild/update verbs. On by default whenever {option}`itera.enable` is
        set; set to `false` to leave {command}`itera rebuild`/`update` behaving
        like a plain {command}`nh os switch` with no configured source.
      '';
    };

    flake = mkOption {
      type = nullOr str;
      default = null;
      example = "github:me/dream";
      description = ''
        The flake {command}`itera rebuild`/`update` build this host from — a
        remote reference such as `github:me/dream` or a local checkout path such
        as {file}`/home/alice/Documents/itera-config` (keep a local checkout
        under a persisted path so it survives the ephemeral root). Also sets the
        `NH_FLAKE` default ({option}`programs.nh.flake`) so a bare
        {command}`nh os switch` resolves too.

        Leave `null` and {command}`nh os switch` (no argument) falls back to
        {file}`/etc/nixos/flake.nix`, which itera never creates — so bare
        {command}`nh os switch` errors on a fresh install. Set it on a real
        install.

        A remote reference is updated with {command}`nh`'s `--refresh` (fetch
        the newest revision); a local path is updated with `--update` (bump its
        {file}`flake.lock`). A value starting with `/` or `.` is treated as a
        local path; anything else as remote.
      '';
    };

    configuration = mkOption {
      type = nullOr str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      example = "dream";
      description = ''
        Which {var}`nixosConfigurations` attribute in {option}`itera.update.flake`
        is THIS host — passed to {command}`nh` as `--hostname` by
        {command}`itera rebuild`/`update`, so a machine built as `dream`
        rebuilds `#dream`. Defaults to the system hostname
        ({option}`itera.networking.hostName`), matching {command}`nh`'s own
        default; set it explicitly when the flake attribute differs from the
        hostname. `null` leaves the choice to {command}`nh` (the hostname).
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    # Feed the NH_FLAKE default so bare `nh os switch` (outside `itera`) resolves.
    programs.nh.flake = mkIf (cfg.flake != null) (mkDefault cfg.flake);

    # cli/itera.sh reads this to assemble the `nh` command line. An absent file
    # (older generations / non-itera systems) makes the wrapper behave like a
    # plain `nh` call.
    environment.etc."itera/update.env".text =
      optionalString (cfg.flake != null) ''
        ITERA_UPDATE_FLAKE=${cfg.flake}
        ITERA_UPDATE_REMOTE=${if isLocal cfg.flake then "0" else "1"}
      ''
      + optionalString (cfg.configuration != null) ''
        ITERA_UPDATE_CONFIGURATION=${cfg.configuration}
      '';
  };
}
