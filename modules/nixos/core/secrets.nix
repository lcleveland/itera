# itera's declarative-secrets battery.
#
# A thin, opinionated wrapper over agenix (bundled by
# `modules/nixos/default.nix`). agenix keeps secrets in the repo as `.age` files
# encrypted to a set of recipients and decrypts them at activation into
# `/run/agenix/<name>` (a tmpfs), so plaintext never touches disk.
#
# This composes with itera's other batteries for free:
#   - impermanence already persists `/etc/ssh/ssh_host_ed25519_key` (see
#     `itera.impermanence` curatedFiles), which is exactly the identity agenix
#     decrypts with — so secrets survive the ephemeral root with zero extra wiring.
#   - decryption lands on tmpfs, matching the hardening posture.
#
# Opt-OUT (default ON) but INERT until used: with no secrets declared the module
# does nothing, so it is safe to leave on. Declare secrets via
# `itera.secrets.secrets.<name>.file = ./secrets/foo.age;` (a passthrough to the
# native `age.secrets` — the full agenix option tree stays reachable because the
# module is bundled, exactly how `itera.disko` leaves `disko.*` in place).
{
  config,
  lib,
  pkgs,
  iteraInputs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    bool
    listOf
    str
    attrsOf
    attrs
    ;

  cfg = config.itera.secrets;
in
{
  options.itera.secrets = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable agenix declarative secrets. On by default whenever
        {option}`itera.enable` is set, but inert until you declare a secret under
        {option}`itera.secrets.secrets`. Set to `false` to drop agenix entirely.
      '';
    };

    identityPaths = mkOption {
      type = listOf str;
      default = [ "/etc/ssh/ssh_host_ed25519_key" ];
      description = ''
        Private-key identities agenix uses to decrypt secrets at activation. The
        default is the host's ed25519 SSH key, which {option}`itera.impermanence`
        already persists across reboots.
      '';
    };

    secrets = mkOption {
      type = attrsOf attrs;
      default = { };
      example = lib.literalExpression ''
        {
          wifi-psk = {
            file = ./secrets/wifi-psk.age;
            owner = "root";
            mode = "0400";
          };
        }
      '';
      description = ''
        Secrets to decrypt, passed straight through to {option}`age.secrets`. Each
        entry names an encrypted `.age` file; agenix decrypts it to
        {file}`/run/agenix/<name>`. See the agenix docs for every per-secret knob
        ({option}`owner`, {option}`group`, {option}`mode`, {option}`path`, …).
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    age.identityPaths = mkDefault cfg.identityPaths;
    age.secrets = cfg.secrets;

    # The agenix CLI (edit/rekey `.age` files). It lives in the agenix flake
    # input, not nixpkgs, so reach it through `iteraInputs` (injected by
    # modules/nixos/default.nix).
    environment.systemPackages = [
      iteraInputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
