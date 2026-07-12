# Evaluation check for itera's desktop batteries (mango + DankMaterialShell).
#
# A full graphical VM boot is heavy and fragile in the NixOS test framework, so
# instead we evaluate a NixOS configuration with the desktop enabled and assert
# the generated config wires everything up: the mango compositor, the DMS shell,
# and the DMS greeter driving greetd with mango as both the greeter's compositor
# and the default session. `nix build` on this derivation forces the evaluation
# and fails loudly if any assertion is false.
{
  pkgs,
  lib,
  self,
  nixpkgs,
}:
let
  eval = nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "25.05";

        itera = {
          # itera.enable alone should bring up the desktop (opt-out): it defaults
          # the shell battery on, which pulls in mango and stands up the greeter.
          enable = true;

          # disko/impermanence are opt-out too, but this eval only exercises the
          # desktop wiring — turn them off so disko's device assertion doesn't
          # block the evaluation (they have their own check in tests/eval.nix).
          disko.enable = false;
          impermanence.enable = false;
        };

        # A hjem user so the home-layer battery (itera.programs.mango) is
        # evaluated — its `enable` follows itera.desktop.mango, so the mango
        # config.conf is generated without any extra opt-in here.
        users.users.alice = {
          isNormalUser = true;
          home = "/home/alice";
        };
        hjem.users.alice.enable = true;
      }
    ];
  };
  cfg = eval.config;

  greetdCommand = cfg.services.greetd.settings.default_session.command;

  mangoUserFiles = cfg.hjem.users.alice.xdg.config.files;

  hasPkg =
    pname: pkgList:
    builtins.any (p: (p.pname or p.name or "") == pname || lib.hasInfix pname (p.name or "")) pkgList;

  checks = {
    # Shell battery pulls in the compositor.
    "mango compositor is enabled" = cfg.programs.mango.enable;
    "DankMaterialShell is enabled" = cfg.programs.dank-material-shell.enable;

    # mango registers a login session with the display manager.
    "mango registers a session package" = cfg.services.displayManager.sessionPackages != [ ];

    # DMS greeter drives greetd, rendered under mango.
    "DMS greeter is enabled" = cfg.programs.dank-material-shell.greeter.enable;
    "greeter runs under mango" = cfg.programs.dank-material-shell.greeter.compositor.name == "mango";
    "greetd is enabled" = cfg.services.greetd.enable;
    "greetd launches the dms-greeter" = lib.hasInfix "dms-greeter" greetdCommand;

    # Post-login session defaults to mango.
    "default session is mango" = cfg.services.displayManager.defaultSession == "mango";

    # Home layer: the mango user config is generated. Probing for the key forces
    # the hjem battery's gated config path (and its `configText`) to evaluate.
    "mango user config is generated" = mangoUserFiles ? "mango/config.conf";

    # Terminal battery ships WezTerm, wires SUPER+t to it, and installs the Nerd
    # Font WezTerm needs for the shell's glyphs.
    "terminal battery is enabled" = cfg.itera.desktop.terminal.enable;
    "SUPER+t spawns wezterm" = cfg.itera.desktop.mango.commands.terminal == "wezterm start";
    "wezterm package is installed" = hasPkg "wezterm" cfg.environment.systemPackages;
    "JetBrains Mono Nerd Font is installed" = hasPkg "jetbrains-mono" cfg.fonts.packages;

    # Home layer: the WezTerm user config renders. Probing the key forces the hjem
    # battery's Lua `configText` (settings + font serialization) to evaluate.
    "wezterm user config is generated" = mangoUserFiles ? "wezterm/wezterm.lua";
    "wezterm config sets the font" =
      lib.hasInfix "wezterm.font('JetBrainsMono Nerd Font')"
        mangoUserFiles."wezterm/wezterm.lua".text;
    "wezterm config sets font_size" =
      lib.hasInfix "config.font_size = 12"
        mangoUserFiles."wezterm/wezterm.lua".text;
  };

  failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
pkgs.runCommand "itera-desktop-eval" { } (
  if failed == [ ] then
    "touch $out"
  else
    throw "itera desktop-battery eval check failed: ${lib.concatStringsSep "; " failed}"
)
