# Tab-completion for the `itera` command (home layer).
#
# The system battery `itera.cli` (modules/nixos/core/cli.nix) puts the `itera`
# command on every user's PATH; this companion home battery gives it completion.
# carapace — itera's external completer in nushell (see
# modules/nixos/core/shell/nushell.nix) — auto-loads specs from
# ~/.config/carapace/specs/, so we drop the consumer spec there. carapace serves
# the same spec to bash/zsh/fish, so completion works in any carapace-backed shell.
#
# Because itera's home collection is applied to every hjem user, enabling
# itera.cli + carapace is enough for every user to get `itera <TAB>`.
#
# Runs inside the hjem user submodule (see modules/hjem/default.nix): `xdg.config.files`
# is unprefixed and `osConfig` is a module arg. Gated on both the command being
# installed and carapace being on — the spec is useless without either.
{
  lib,
  osConfig ? null,
  ...
}:
let
  inherit (lib.modules) mkIf;

  cliEnabled = osConfig.itera.cli.enable or false;
  carapaceEnabled =
    (osConfig.itera.shell.nushell.enable or false)
    && (osConfig.itera.shell.nushell.carapace.enable or false);
in
{
  config = mkIf (cliEnabled && carapaceEnabled) {
    # Explicit clobber so the declarative spec survives impermanence (same
    # rationale as the nushell config files).
    xdg.config.files."carapace/specs/itera.yaml" = {
      source = ../../../cli/itera-consumer.carapace.yaml;
      clobber = true;
    };
  };
}
