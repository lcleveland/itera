# Evaluation check for itera's opt-in service/system batteries:
# printing, gaming, local-AI (ollama/open-webui), and the keyboard-layout battery.
#
# Each battery is exercised in its own `mkConfig` so the enable-gating and the
# generated NixOS config can be asserted independently. `nix build` forces
# evaluation and fails loudly if any assertion is false.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  inherit
    (import ./lib.nix {
      inherit
        pkgs
        lib
        self
        nixpkgs
        ;
    })
    mkConfig
    mkCheckDrv
    ;

  hasName = name: list: builtins.elem name (map lib.getName list);

  # ── printing ─────────────────────────────────────────────────────────────
  printing = mkConfig [ { itera.printing.enable = true; } ];

  # ── gaming ───────────────────────────────────────────────────────────────
  gaming = mkConfig [ { itera.gaming.enable = true; } ];

  # ── local AI: CPU path (nvidia off) ───────────────────────────────────────
  aiCpu = mkConfig [
    {
      itera.ai.ollama.enable = true;
      itera.ai.openWebui.enable = true;
    }
  ];

  # ── local AI: explicit CUDA without the nvidia battery → warning ──────────
  aiCudaNoGpu = mkConfig [
    {
      itera.ai.ollama.enable = true;
      itera.ai.ollama.acceleration = "cuda";
    }
  ];

  # ── AI: Claude Code CLI (opt-in, independent of ollama) ───────────────────
  claude = mkConfig [ { itera.ai.claude.enable = true; } ];

  # ── AI: Claude ACP adapter (opt-in, independent of the CLI) ───────────────
  claudeAcp = mkConfig [ { itera.ai.claude.acp.enable = true; } ];

  # ── keyboard ──────────────────────────────────────────────────────────────
  keyboard = mkConfig [ { itera.keyboard.variant = "colemak_dh"; } ];

  # ── firmware (opt-out) ─────────────────────────────────────────────────────
  firmwareOff = mkConfig [ { itera.firmware.enable = false; } ];

  checks = {
    # ── printing ─────────────────────────────────────────────────────────
    "printing off by default" = !(mkConfig [ ]).services.printing.enable;
    "printing enables CUPS" = printing.services.printing.enable;
    "printing ships the default HP driver" = hasName "hplip" printing.services.printing.drivers;
    "printing enables avahi discovery" = printing.services.avahi.enable;
    "printing opens the discovery firewall" = printing.services.avahi.openFirewall;
    "printing installs the GUI by default" = printing.services.system-config-printer.enable;

    # ── gaming ─────────────────────────────────────────────────────────────
    "gaming off by default" = !(mkConfig [ ]).programs.steam.enable;
    "gaming enables Steam" = gaming.programs.steam.enable;
    "gaming ships Proton-GE" = hasName "proton-ge-bin" gaming.programs.steam.extraCompatPackages;
    "gaming enables gamescope" = gaming.programs.gamescope.enable;
    "gaming enables gamemode" = gaming.programs.gamemode.enable;

    # ── local AI ───────────────────────────────────────────────────────────
    "ai off by default" = !(mkConfig [ ]).services.ollama.enable;
    "ai enables ollama" = aiCpu.services.ollama.enable;
    "ai enables open-webui" = aiCpu.services.open-webui.enable;
    # `ollama` and `ollama-cuda` share the pname "ollama", so distinguish the
    # selected build by its derivation, not its name. nvidia off + auto must pick
    # a DIFFERENT build than an explicit cuda selection — proving the branch.
    "ai auto picks a non-CUDA build without a GPU" =
      aiCpu.services.ollama.package.drvPath != aiCudaNoGpu.services.ollama.package.drvPath;
    "ai auto build matches the plain ollama package" =
      lib.getName aiCpu.services.ollama.package == "ollama";
    # Explicit CUDA without the nvidia battery warns about the CPU fallback.
    "ai warns on CUDA without nvidia" = lib.any (
      w: lib.hasInfix "fall back to CPU" w
    ) aiCudaNoGpu.warnings;
    # Claude Code CLI is opt-in: absent by default, on the system PATH once enabled.
    "claude cli off by default" = !(hasName "claude-code" (mkConfig [ ]).environment.systemPackages);
    "claude cli installed when opted in" = hasName "claude-code" claude.environment.systemPackages;
    # Claude ACP adapter: off by default, follows the CLI toggle, and can be
    # enabled on its own.
    "claude acp adapter off by default" =
      !(hasName "claude-agent-acp" (mkConfig [ ]).environment.systemPackages);
    "claude acp adapter follows the CLI toggle" =
      hasName "claude-agent-acp" claude.environment.systemPackages;
    "claude acp adapter installable on its own" =
      hasName "claude-agent-acp" claudeAcp.environment.systemPackages;

    # ── firmware ───────────────────────────────────────────────────────────
    # Opt-out battery: fwupd is on by default and turns off cleanly.
    "fwupd on by default" = (mkConfig [ ]).services.fwupd.enable;
    "fwupd disabled when battery off" = !firmwareOff.services.fwupd.enable;

    # ── keyboard ───────────────────────────────────────────────────────────
    "keyboard defaults to us" = (mkConfig [ ]).services.xserver.xkb.layout == "us";
    "keyboard variant applied to xkb" = keyboard.services.xserver.xkb.variant == "colemak_dh";
    "keyboard drives the console layout" = keyboard.console.useXkbConfig;

    # ── mango/greeter xkb renderer unit ────────────────────────────────────
    "xkb renderer emits variant line" = lib.hasInfix "xkb_rules_variant=colemak_dh" (
      self.lib.mango.renderXkb {
        layout = "us";
        variant = "colemak_dh";
      }
    );
    "xkb renderer empty → omitted" = self.lib.mango.renderXkb { } == "";
  };
in
mkCheckDrv "itera-services-eval" checks
