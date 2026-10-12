# A planted violation of both look lints (flake/checks.nix): a colour literal
# and a read of `itera.look` outside lib/look.nix. The lints must fail on it.
{ osConfig, ... }:
{
  color = "#c0ffee";
  inherit (osConfig.itera.look) mode;
}
