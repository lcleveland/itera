# itera's AI battery.
#
# Runs local LLM inference (ollama) and, optionally, the open-webui chat UI in
# front of it, plus the Claude Code CLI. All of it is opt-IN (off by default):
# the local-inference paths pull in large model-runtime packages wanted only on a
# workstation with the hardware for it, and the CLI is a per-preference tool.
#
# GPU acceleration: `ollama.acceleration` selects the ollama build/package. `auto`
# picks the CUDA build when the nvidia battery is on and the plain (CPU) build
# otherwise. This composes with `itera.nvidia.containerToolkit` for containerised
# GPU workloads. A warning fires if the CUDA build is requested without the nvidia
# battery, since it then just falls back to CPU at runtime with no GPU offload.
#
# Claude Code (`claude.enable`) installs Anthropic's agentic CLI system-wide.
# Under itera's default-on impermanence its per-user state (`~/.claude`,
# `~/.claude.json`) is already persisted, so the login survives the wiped root.
#
# Claude ACP (`claude.acp.enable`) installs the `claude-agent-acp` adapter, which
# plugs Claude Code into an Agent Client Protocol client — namely Zed's agent
# panel. It defaults to following `claude.enable` (enabling the CLI brings the
# adapter too), and can be toggled independently. When the editor battery
# (`itera.desktop.editor`) is on it is auto-registered under Zed's `agent_servers`
# (see `modules/programs/zed.nix`). The adapter bundles its own `claude-code`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;
  inherit (lib.types) bool enum;

  cfg = config.itera.ai;

  nvidiaOn = config.itera.nvidia.enable or false;
  # `auto` resolves to the CUDA build when the GPU battery is present, else CPU.
  accel =
    if cfg.ollama.acceleration == "auto" then
      (if nvidiaOn then "cuda" else "cpu")
    else
      cfg.ollama.acceleration;
  ollamaPackage =
    {
      cpu = pkgs.ollama;
      cuda = pkgs.ollama-cuda;
      rocm = pkgs.ollama-rocm;
    }
    .${accel};
in
{
  options.itera.ai = {
    ollama = {
      enable = mkEnableOption "the ollama local LLM runtime";

      acceleration = mkOption {
        type = enum [
          "auto"
          "cpu"
          "cuda"
          "rocm"
        ];
        default = "auto";
        description = ''
          Which ollama build to run. `auto` (the default) picks the `cuda` build
          when {option}`itera.nvidia.enable` is set and the plain `cpu` build
          otherwise. Selects {option}`services.ollama.package`.
        '';
      };
    };

    openWebui = {
      enable = mkEnableOption "the open-webui chat UI (front-end for ollama)";
    };

    claude = {
      enable = mkEnableOption "the Claude Code CLI (`claude`), installed system-wide";

      acp.enable = mkOption {
        type = bool;
        default = cfg.claude.enable;
        defaultText = lib.literalExpression "config.itera.ai.claude.enable";
        description = ''
          Whether to install the Claude Code ACP adapter (`claude-agent-acp`),
          which plugs Claude Code into Zed's agent panel over the Agent Client
          Protocol. Defaults to following {option}`itera.ai.claude.enable`. When
          the editor battery (`itera.desktop.editor`) is on it is auto-registered
          under Zed's `agent_servers` (see `modules/programs/zed.nix`). The adapter
          bundles its own `claude-code`, so it works even without
          {option}`itera.ai.claude.enable`.
        '';
      };
    };
  };

  config = mkIf config.itera.enable (mkMerge [
    (mkIf cfg.ollama.enable {
      services.ollama = {
        enable = mkDefault true;
        package = mkDefault ollamaPackage;
      };

      warnings = lib.optional (cfg.ollama.acceleration == "cuda" && !nvidiaOn) (
        "itera.ai.ollama.acceleration = \"cuda\" but itera.nvidia is off — the CUDA "
        + "ollama build will fall back to CPU. Enable itera.nvidia for GPU offload, "
        + "or set acceleration = \"cpu\"."
      );
    })

    (mkIf cfg.openWebui.enable {
      services.open-webui.enable = mkDefault true;
    })

    (mkIf cfg.claude.enable {
      environment.systemPackages = [ pkgs.claude-code ];
    })

    (mkIf cfg.claude.acp.enable {
      environment.systemPackages = [ pkgs.claude-agent-acp ];
    })
  ]);
}
