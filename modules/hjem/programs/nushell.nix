# itera's nushell user-config battery (home layer).
#
# The system battery `itera.shell.nushell` installs nushell + carapace and makes
# nushell the default login shell; this hjem battery writes the per-user config
# nushell reads from {file}`~/.config/nushell/` — chiefly the carapace hookup that
# gives external commands (git, docker, systemctl, …) tab completion. Because
# itera's home collection is applied to every hjem user, enabling the system
# battery is enough for every user to inherit these defaults.
#
# Completion model: nushell natively completes its own commands, flags, paths, and
# variables. carapace is wired in as the *external* completer via a build-time
# generated init script (`carapace _carapace nushell`, mirroring home-manager's
# `programs.carapace.enableNushellIntegration`). That script assigns
# `$env.config.completions.external.{enable,completer}`, so config.nu must MUTATE
# individual `$env.config` fields rather than replace the whole record — replacing
# it would clobber carapace's assignment.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `pkgs` are module args.
# Enable tracks the system toggle by default.
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool lines;

  cfg = config.itera.programs.nushell;

  systemEnabled = osConfig.itera.shell.nushell.enable or false;
  carapaceEnabled = systemEnabled && (osConfig.itera.shell.nushell.carapace.enable or false);
  carapacePkg = osConfig.itera.shell.nushell.carapace.package or pkgs.carapace;

  # Pre-generate carapace's nushell integration at build time (deterministic and
  # reproducible — no `carapace | save` on every shell startup). The script
  # defines the completer closure and wires it into `$env.config.completions`; it
  # invokes `carapace` at runtime, which the system battery puts on PATH.
  carapaceInit = pkgs.runCommand "carapace-init.nu" {
    nativeBuildInputs = [ carapacePkg ];
  } "carapace _carapace nushell > $out";

  # config.nu — mutate individual fields so carapace's external-completer
  # assignment (sourced below) is preserved.
  configText = ''
    $env.config.show_banner = ${if cfg.showBanner then "true" else "false"}
  ''
  + lib.optionalString carapaceEnabled ''
    source carapace-init.nu
  ''
  + lib.optionalString (cfg.extraConfig != "") "\n${cfg.extraConfig}\n";
in
{
  options.itera.programs.nushell = {
    enable =
      mkEnableOption "itera's nushell user configuration"
      # Follow the system shell toggle by default: enabling
      # `itera.shell.nushell` is enough to get the matching home config.
      // {
        default = systemEnabled;
        defaultText = lib.literalExpression "osConfig.itera.shell.nushell.enable";
      };

    showBanner = mkOption {
      type = bool;
      default = false;
      description = "Show nushell's startup banner (`$env.config.show_banner`).";
    };

    extraEnv = mkOption {
      type = lines;
      default = "";
      description = "Arbitrary nushell appended to {file}`~/.config/nushell/env.nu`.";
    };

    extraConfig = mkOption {
      type = lines;
      default = "";
      description = ''
        Arbitrary nushell appended to {file}`~/.config/nushell/config.nu`, after
        itera's defaults and the carapace hookup. Mutate `$env.config` fields
        individually rather than reassigning the whole record.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Warn (don't fail) if the home config is on but the system shell battery is
    # off — the config would be written for a nushell that isn't installed.
    warnings = lib.optional (!systemEnabled) ''
      itera.programs.nushell is enabled for a user but
      itera.shell.nushell.enable is false — the nushell config will be written to
      $HOME without nushell being installed.
    '';

    # hjem sinks: nushell reads these from ~/.config/nushell/. Explicit clobber so
    # the declarative config survives impermanence (same rationale as wezterm/mango).
    xdg.config.files = {
      "nushell/env.nu" = {
        text = cfg.extraEnv;
        clobber = true;
      };

      "nushell/config.nu" = {
        text = configText;
        clobber = true;
      };
    }
    // lib.optionalAttrs carapaceEnabled {
      "nushell/carapace-init.nu" = {
        source = carapaceInit;
        clobber = true;
      };
    };
  };
}
