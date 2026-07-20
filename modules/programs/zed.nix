# Curated-program registration for Zed (the editor battery's home config).
#
# Declares Zed's curated settings ONCE and exposes them at two levels:
#   - `itera.programs.zed.*`               — system-wide default for every user
#   - `itera.users.<name>.programs.zed.*`  — per-user override (wins per key)
#
# The hjem battery `modules/hjem/programs/zed.nix` reads the merged result via
# `osConfig` and writes `~/.config/zed/settings.json`.
#
# See lib/programs.nix for the framework. NOT a NixOS module — a registration
# record consumed by `modules/programs/default.nix`.
{ lib, iteraLib }:
let
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkDefault;
  inherit (lib.types) attrsOf anything bool;
in
iteraLib.programs.mkCuratedProgram {
  name = "zed";

  fields = {
    settings = {
      type = attrsOf anything;
      attrs = true;
      example = {
        vim_mode = true;
        buffer_font_size = 14;
      };
      description = ''
        Zed settings, written to {file}`$XDG_CONFIG_HOME/zed/settings.json`. The
        system-wide default ({option}`itera.programs.zed.settings`) and each
        per-user override merge per key. itera's only opinionated default is
        disabling telemetry. The dedicated {option}`agent` and
        {option}`agentServers` options are merged in on top of this under their
        respective settings keys.
      '';
    };

    agent = {
      type = attrsOf anything;
      attrs = true;
      example = {
        default_profile = "ask";
        default_model = {
          provider = "anthropic";
          model = "claude-sonnet-4";
        };
      };
      description = ''
        Zed's built-in Agent Panel configuration, written to the `agent` key of
        {file}`settings.json`. System-wide ({option}`itera.programs.zed.agent`)
        and per-user values merge per key.
      '';
    };

    agentServers = {
      type = attrsOf anything;
      attrs = true;
      example = {
        claude = {
          command = "claude-agent-acp";
          args = [ ];
          env = { };
        };
      };
      description = ''
        External ACP agent servers, written to the `agent_servers` key of
        {file}`settings.json` — this is how an external coding agent such as
        Claude Code plugs into Zed's agent panel. System-wide
        ({option}`itera.programs.zed.agentServers`) and per-user values merge per
        key.
      '';
    };
  };

  # Opinionated "batteries-included" defaults (per-key mkDefault so explicit values
  # — system-wide or per-user — override):
  #   * telemetry off, matching itera's privacy-focused stack; and
  #   * when the editor battery's Nix language server is enabled, wire Zed to use
  #     nixd for `.nix` files. The `nixd`/`nixfmt` binaries are installed on `PATH`
  #     by the system half (`modules/nixos/desktop/editor.nix`); here we just select
  #     nixd (disabling Zed's default nil) and, if requested, format-on-save via
  #     nixfmt. `auto_install_extensions.nix` ensures Zed's Nix grammar + LSP
  #     registration is present so the server actually attaches.
  systemConfig =
    config:
    let
      editor = config.itera.desktop.editor;
      nixLsp = editor.enable && editor.nixLanguageServer.enable;
      # When the Claude ACP battery is on and Zed is installed, register the
      # adapter as an external agent so it shows up in Zed's agent panel with no
      # further config. `mkDefault` lets an explicit system/per-user value win.
      claudeAcp = editor.enable && config.itera.ai.claude.acp.enable;
    in
    {
      settings = {
        telemetry = {
          diagnostics = mkDefault false;
          metrics = mkDefault false;
        };
      }
      // lib.optionalAttrs nixLsp {
        auto_install_extensions.nix = mkDefault true;
        languages.Nix = {
          language_servers = mkDefault [
            "nixd"
            "!nil"
          ];
        }
        // lib.optionalAttrs editor.nixLanguageServer.formatOnSave {
          formatter = mkDefault {
            external = {
              command = "nixfmt";
              arguments = [ ];
            };
          };
          format_on_save = mkDefault "on";
        };
        lsp.nixd = mkDefault { };
      };
    }
    // lib.optionalAttrs claudeAcp {
      agentServers.claude = mkDefault {
        command = "claude-agent-acp";
        args = [ ];
        env = { };
      };
    };

  # Per-user-only escape hatch (no system-wide counterpart): let a user opt the
  # rendered settings.json out of clobbering so Zed's GUI can own it after first
  # write (add agents / edit settings in-app and have them stick). Default true
  # keeps the declarative value winning every rebuild, matching the DMS battery.
  userExtra = {
    clobber = mkOption {
      type = bool;
      default = true;
      description = ''
        Whether the rendered {file}`~/.config/zed/settings.json` clobbers an
        existing file on rebuild. `true` (default) keeps itera's declarative
        settings authoritative — Zed cannot edit them, since the file is a
        read-only Nix-store symlink. Set to `false` to let Zed own the file after
        the first write (so in-app settings/agent changes persist); note that
        under itera's default impermanence a `false` file is restored from
        {file}`/persist` and then frozen at its first-linked content, so the GUI,
        not later itera config changes, becomes the source of truth.
      '';
    };
  };
}
