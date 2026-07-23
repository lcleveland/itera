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

  # itera.enable alone brings up the desktop (opt-out): it defaults the shell
  # battery on, which pulls in mango and stands up the greeter. disko/impermanence
  # stay off (the mkConfig default) — this eval only exercises the desktop wiring.
  cfg = mkConfig [
    {
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

  # Same host with the editor's Nix language server opted out, to assert the
  # negative: no nixd on PATH and no Nix settings written into Zed's config.
  cfgNoNixLsp = mkConfig [
    { itera.desktop.editor.nixLanguageServer.enable = false; }
  ];

  # Clipboard bridge opted out, and with select-to-copy opted in, to assert the
  # service gating in both directions.
  cfgClipboardOff = mkConfig [
    { itera.desktop.clipboard.enable = false; }
  ];
  cfgSelectToCopy = mkConfig [
    { itera.desktop.clipboard.selectToCopy = true; }
  ];

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
    "DMS greeter is enabled" = cfg.programs.dms-greeter.enable;
    "greeter runs under mango" = cfg.programs.dms-greeter.compositor.name == "mango";
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

    # File-manager battery ships Nemo (default ON) and wires SUPER+f to it.
    "file-manager battery is enabled" = cfg.itera.desktop.fileManager.enable;
    "SUPER+f spawns nemo" = cfg.itera.desktop.mango.commands.fileBrowser == "nemo";

    # Editor battery ships Zed (default ON), claims the text handler, and wires
    # SUPER+e to it. It deliberately does NOT set EDITOR/VISUAL (GUI-default only).
    "editor battery is enabled" = cfg.itera.desktop.editor.enable;
    "SUPER+e spawns zeditor" = cfg.itera.desktop.mango.commands.editor == "zeditor";
    "zed-editor package is installed" = hasPkg "zed-editor" cfg.environment.systemPackages;
    "zed is the default text/plain handler" =
      cfg.xdg.mime.defaultApplications."text/plain" == "dev.zed.Zed.desktop";

    # Home layer: the WezTerm user config renders. Probing the key forces the hjem
    # battery's Lua `configText` (settings + font serialization) to evaluate.
    "wezterm user config is generated" = mangoUserFiles ? "wezterm/wezterm.lua";
    "wezterm config sets the font" =
      lib.hasInfix "wezterm.font('JetBrainsMono Nerd Font')"
        mangoUserFiles."wezterm/wezterm.lua".text;
    "wezterm config sets font_size" =
      lib.hasInfix "config.font_size = 12"
        mangoUserFiles."wezterm/wezterm.lua".text;

    # Home layer: the Zed user config renders. Probing the key forces the hjem
    # battery's gated config path (settings serialization) to evaluate.
    "zed user config is generated" = mangoUserFiles ? "zed/settings.json";

    # Nix language server (default ON): nixd + nixfmt land on PATH and Zed's
    # settings select nixd (disabling nil) with nixfmt format-on-save.
    "nixd is installed" = hasPkg "nixd" cfg.environment.systemPackages;
    "nixfmt is installed" = hasPkg "nixfmt" cfg.environment.systemPackages;
    "zed selects nixd for Nix" =
      cfg.itera.programs.zed.settings.languages.Nix.language_servers == [
        "nixd"
        "!nil"
      ];
    "zed formats Nix on save with nixfmt" =
      cfg.itera.programs.zed.settings.languages.Nix.format_on_save == "on"
      && cfg.itera.programs.zed.settings.languages.Nix.formatter.external.command == "nixfmt";

    # Opting the Nix LSP out drops the binary and writes no Nix settings.
    "nixd absent when disabled" = !hasPkg "nixd" cfgNoNixLsp.environment.systemPackages;
    "no Nix settings when disabled" = !(cfgNoNixLsp.itera.programs.zed.settings ? languages);

    # Clipboard bridge battery (default ON with the desktop): ships wl-clipboard
    # and the two always-on bridge user services (Wayland→X11 poll-free watch, and
    # the CLIPBOARD→PRIMARY autocutsel). Gated off with the desktop or its toggle.
    "clipboard bridge battery is enabled" = cfg.itera.desktop.clipboard.enable;
    "wl-clipboard is installed by default" = hasPkg "wl-clipboard" cfg.environment.systemPackages;
    "clipboard wayland-to-x11 bridge service present" =
      cfg.systemd.user.services ? "itera-clipboard-wayland-to-x11";
    "clipboard autocutsel-primary service present" =
      cfg.systemd.user.services ? "itera-clipboard-autocutsel-primary";
    # select-to-copy is off by default (no PRIMARY→CLIPBOARD service), and opting
    # it in adds exactly that service.
    "select-to-copy is off by default" =
      !(cfg.systemd.user.services ? "itera-clipboard-autocutsel-clipboard");
    "select-to-copy adds the PRIMARY->CLIPBOARD service" =
      cfgSelectToCopy.systemd.user.services ? "itera-clipboard-autocutsel-clipboard";
    # Gated off: no bridge services when the battery is disabled.
    "clipboard bridge gated off when disabled" =
      !(cfgClipboardOff.systemd.user.services ? "itera-clipboard-wayland-to-x11")
      && !(cfgClipboardOff.systemd.user.services ? "itera-clipboard-autocutsel-primary");
  };

in
mkCheckDrv "itera-desktop-eval" checks
