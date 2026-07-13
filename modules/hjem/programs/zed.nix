# itera's Zed user-config battery (home layer).
#
# The system battery `itera.desktop.editor` installs Zed, claims the text-file MIME
# handlers, and wires the mango `SUPER+e` bind; this hjem battery writes the
# per-user {file}`~/.config/zed/settings.json` that Zed reads. Because itera's home
# collection is applied to every hjem user, enabling the desktop is enough for every
# user to inherit these defaults — no per-user wiring needed.
#
# Config format: Zed's config is JSON, so `settings` is rendered with nixpkgs'
# `pkgs.formats.json` generator (same idiom as the `_example.nix` reference). itera's
# opinionated defaults are merged underneath via `mkDefault` so anything the user
# sets wins.
#
# The only opinionated default here is disabling telemetry — matching itera's
# privacy-focused stack (ungoogled-chromium). No font / format-on-save opinions are
# imposed; Zed's own defaults stand and it already respects the repo's
# `.editorconfig`.
#
# Runs inside the hjem user submodule (see `modules/hjem/default.nix`): sinks like
# `xdg.config.files` are unprefixed and `osConfig` / `pkgs` are module args. Enable
# tracks the system toggle by default.
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;

  json = pkgs.formats.json { };

  cfg = config.itera.programs.zed;

  systemEnabled = osConfig.itera.desktop.editor.enable or false;
in
{
  options.itera.programs.zed = {
    enable =
      mkEnableOption "itera's Zed user configuration"
      # Follow the system editor toggle by default: enabling
      # `itera.desktop.editor` is enough to get the matching home config.
      // {
        default = systemEnabled;
        defaultText = lib.literalExpression "osConfig.itera.desktop.editor.enable";
      };

    settings = mkOption {
      inherit (json) type;
      default = { };
      example = {
        vim_mode = true;
        buffer_font_size = 14;
      };
      description = ''
        Written verbatim to {file}`$XDG_CONFIG_HOME/zed/settings.json`. itera's
        opinionated defaults (telemetry disabled) are merged underneath via
        `mkDefault`, so anything set here wins — the module stays opt-out.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Warn (don't fail) if the home config is on but the system editor is off —
    # the config would be written for a Zed that isn't installed.
    warnings = lib.optional (!systemEnabled) ''
      itera.programs.zed is enabled for a user but itera.desktop.editor.enable is
      false — the Zed settings will be written to $HOME without Zed being installed.
    '';

    # Opinionated "batteries-included" default: telemetry off. Explicit user values
    # override.
    itera.programs.zed.settings.telemetry = {
      diagnostics = mkDefault false;
      metrics = mkDefault false;
    };

    xdg.config.files."zed/settings.json" = {
      source = json.generate "zed-settings.json" cfg.settings;
      # Explicit clobber — same rationale as the wezterm/mango batteries: replace
      # any pre-existing settings.json rather than letting hjem refuse to overwrite.
      clobber = true;
    };
  };
}
