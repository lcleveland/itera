# itera's sops-nix secrets battery — the multi-secret sibling of `itera.secrets`.
#
# Where agenix (`itera.secrets`) encrypts ONE secret per `.age` file, sops-nix
# keeps MANY secrets in a SINGLE encrypted YAML/JSON file and encrypts only the
# values, so the file stays diffable and reviewable in git. That is usually what
# multi-host / multi-operator setups want, so itera ships both engines and lets
# you pick per host. They are independent and can run side by side — nothing
# here touches `itera.secrets`.
#
# This composes with itera's other batteries exactly like the agenix battery:
#   - the default decryption identity is the host's ed25519 SSH key, which
#     `itera.impermanence` already persists (see `curatedFiles`), so secrets
#     survive the ephemeral root with zero extra wiring.
#   - decryption lands on tmpfs (`/run/secrets`), matching the hardening posture.
#   - a custom `keyFile` is added to the persisted set by `itera.impermanence`,
#     so pointing this at your own age key does not silently break on reboot.
#
# Opt-IN (default OFF), and INERT even when on until a secret is declared:
# agenix stays itera's default engine, so nothing here activates until you ask
# for it. Turn it on with `itera.sops.enable = true` and declare secrets via
# `itera.sops.secrets.<name>` (a passthrough to the native `sops.secrets` — the
# full sops-nix option tree stays reachable because the module is bundled,
# exactly how `itera.disko` leaves `disko.*` in place).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.types)
    bool
    listOf
    str
    path
    nullOr
    attrsOf
    attrs
    ;

  cfg = config.itera.sops;
in
{
  options.itera.sops = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable sops-nix declarative secrets. OFF by default — agenix
        ({option}`itera.secrets`) is itera's default secrets engine, and this is
        the alternative for setups that would rather keep many secrets in one
        encrypted file. Turning it on is still inert until you declare a secret
        under {option}`itera.sops.secrets`. The two engines are independent and
        may both be enabled.
      '';
    };

    defaultSopsFile = mkOption {
      type = nullOr path;
      default = null;
      example = lib.literalExpression "./secrets/secrets.yaml";
      description = ''
        The encrypted file every secret is read from unless it sets its own
        `sopsFile`. Left unset when `null`, so the battery stays inert. Note
        that sops-nix validates this file at evaluation time
        ({option}`sops.validateSopsFiles`), so it must be in the Nix store —
        a path literal inside your flake is what you want.
      '';
    };

    defaultSopsFormat = mkOption {
      type = str;
      default = "yaml";
      example = "json";
      description = ''
        Format of {option}`itera.sops.defaultSopsFile` — `yaml`, `json`,
        `binary`, `dotenv` or `ini`. Per-secret `format` overrides it.
      '';
    };

    sshKeyPaths = mkOption {
      type = listOf str;
      default = [ "/etc/ssh/ssh_host_ed25519_key" ];
      description = ''
        SSH host keys converted to age identities to decrypt with. The default
        is the host's ed25519 key, which {option}`itera.impermanence` already
        persists across reboots — the same identity {option}`itera.secrets`
        (agenix) uses, so one host key serves both engines.

        Derive the matching age *recipient* for your `.sops.yaml` with
        {command}`ssh-to-age` (installed by this battery), e.g.
        {command}`ssh-keyscan localhost | ssh-to-age`.
      '';
    };

    keyFile = mkOption {
      type = nullOr str;
      default = null;
      example = "/var/lib/sops-nix/key.txt";
      description = ''
        A dedicated age key file to decrypt with, as an alternative (or in
        addition) to {option}`itera.sops.sshKeyPaths`. When set,
        {option}`itera.impermanence` persists this file so it survives the
        ephemeral root. Must NOT live in the Nix store — that would make the
        decryption key world-readable.
      '';
    };

    generateKey = mkOption {
      type = bool;
      default = false;
      description = ''
        Generate {option}`itera.sops.keyFile` if it does not exist yet, instead
        of requiring it to be provisioned beforehand. Note that a freshly
        generated key decrypts nothing until you add its recipient to
        `.sops.yaml` and re-encrypt.
      '';
    };

    secrets = mkOption {
      type = attrsOf attrs;
      default = { };
      example = lib.literalExpression ''
        {
          wifi-psk = {
            owner = "root";
            mode = "0400";
          };
          # a key nested under `services:` in the sops file, from another file
          api-token = {
            key = "services/api-token";
            sopsFile = ./secrets/services.yaml;
          };
        }
      '';
      description = ''
        Secrets to decrypt, passed straight through to {option}`sops.secrets`.
        Each entry names a key inside the sops file (the attribute name is the
        key unless `key` says otherwise); sops-nix decrypts it to
        {file}`/run/secrets/<name>`. See the sops-nix docs for every per-secret
        knob ({option}`owner`, {option}`group`, {option}`mode`, {option}`path`,
        {option}`sopsFile`, {option}`key`, {option}`restartUnits`, …).
      '';
    };
  };

  config = mkIf (config.itera.enable && cfg.enable) {
    sops = {
      # `defaultSopsFile` is a plain `path` upstream with no default, so it must
      # stay UNDEFINED rather than be defined as null while the battery is inert.
      defaultSopsFile = mkIf (cfg.defaultSopsFile != null) cfg.defaultSopsFile;
      defaultSopsFormat = mkDefault cfg.defaultSopsFormat;

      age = {
        sshKeyPaths = mkDefault cfg.sshKeyPaths;
        keyFile = mkDefault cfg.keyFile;
        generateKey = mkDefault cfg.generateKey;
      };

      # Age-only by default. sops-nix otherwise defaults `gnupg.sshKeyPaths` to
      # the host's RSA host key whenever openssh is on, quietly adding a second
      # (GnuPG) decryption path itera never asked for. mkDefault, so a consumer
      # who does want GnuPG can still set it.
      gnupg.sshKeyPaths = mkDefault [ ];

      inherit (cfg) secrets;
    };

    # The sops CLI (create/edit/rekey the encrypted files) plus ssh-to-age, which
    # converts an SSH host key into the age recipient `.sops.yaml` needs — the
    # step the sshKeyPaths default above implies. Both live in nixpkgs, so unlike
    # the agenix CLI they need no `iteraInputs` detour.
    environment.systemPackages = [
      pkgs.sops
      pkgs.ssh-to-age
    ];
  };
}
