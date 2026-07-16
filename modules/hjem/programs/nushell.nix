# itera's nushell user-config renderer (home layer).
#
# The system battery `itera.shell.nushell` installs nushell + carapace and makes
# nushell the default login shell; the curated-program registration
# `modules/programs/nushell.nix` declares the knobs (system-wide
# `itera.programs.nushell.*` + per-user `itera.users.<name>.programs.nushell.*`).
# THIS battery is the renderer: it reads the merged result out of `osConfig` and
# writes the per-user config under {file}`~/.config/nushell/` — chiefly the carapace
# hookup that gives external commands (git, docker, …) tab completion.
#
# Completion model: nushell natively completes its own commands, flags, paths, and
# variables. carapace is wired in as the *external* completer via a build-time
# generated init script (`carapace _carapace nushell`). That script assigns
# `$env.config.completions.external.{enable,completer}`, so config.nu must MUTATE
# individual `$env.config` fields rather than replace the whole record.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `pkgs` / `name` are module args.
# Declares NO options (the schema lives in the registration); enablement follows the
# system shell toggle.
{
  lib,
  pkgs,
  osConfig ? null,
  name,
  ...
}:
let
  inherit (lib.modules) mkIf;

  enable = osConfig.itera.shell.nushell.enable or false;
  carapaceEnabled = enable && (osConfig.itera.shell.nushell.carapace.enable or false);
  carapacePkg = osConfig.itera.shell.nushell.carapace.package or pkgs.carapace;

  sys = osConfig.itera.programs.nushell or { };
  usr = osConfig.itera.users.${name}.programs.nushell or { };

  # scalar overrides: per-user value wins when set (non-null), else system.
  showBanner = if (usr.showBanner or null) != null then usr.showBanner else (sys.showBanner or false);
  extraEnv = if (usr.extraEnv or null) != null then usr.extraEnv else (sys.extraEnv or "");
  extraConfig =
    if (usr.extraConfig or null) != null then usr.extraConfig else (sys.extraConfig or "");

  # Pre-generate carapace's nushell integration at build time (deterministic and
  # reproducible — no `carapace | save` on every shell startup). The script defines
  # the completer closure and wires it into `$env.config.completions`; it invokes
  # `carapace` at runtime, which the system battery puts on PATH.
  carapaceInit = pkgs.runCommand "carapace-init.nu" {
    nativeBuildInputs = [ carapacePkg ];
  } "carapace _carapace nushell > $out";

  # config.nu — mutate individual fields so carapace's external-completer assignment
  # (sourced below) is preserved.
  configText = ''
    $env.config.show_banner = ${if showBanner then "true" else "false"}
  ''
  + lib.optionalString carapaceEnabled ''
    source carapace-init.nu
  ''
  + lib.optionalString (extraConfig != "") "\n${extraConfig}\n";
in
{
  config = mkIf enable {
    # hjem sinks: nushell reads these from ~/.config/nushell/. Explicit clobber so
    # the declarative config survives impermanence (same rationale as the mango battery).
    xdg.config.files = {
      "nushell/env.nu" = {
        text = extraEnv;
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
