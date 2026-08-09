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

  # No compositor at all, to assert the session target is gated on the battery
  # rather than declared unconditionally.
  cfgNoDesktop = mkConfig [
    { itera.desktop.dankMaterialShell.enable = false; }
  ];

  # The appearance battery flipped to light, and switched off entirely, to assert
  # Zed's color scheme follows it in both directions.
  cfgLightTheme = mkConfig [
    { itera.desktop.theme.dark = false; }
  ];
  cfgNoTheme = mkConfig [
    { itera.desktop.theme.enable = false; }
  ];

  # Clipboard bridge opted out, and with select-to-copy opted in, to assert the
  # service gating in both directions. selectToCopy stays ON in the opted-out
  # fixture so the autocutsel half of the gate is actually exercised rather than
  # passing vacuously (it is off by default).
  cfgClipboardOff = mkConfig [
    {
      itera.desktop.clipboard.enable = false;
      itera.desktop.clipboard.selectToCopy = true;
    }
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

    # Session target: greetd execs mango directly, so itera has to bring up
    # `graphical-session.target` itself — xdg-desktop-portal 1.22+ has
    # `Requisite=` on it and cannot start otherwise (no file picker, no
    # screencast, no color-scheme). The binding is what pulls the real target up.
    "mango-session target is declared" = cfg.systemd.user.targets ? "mango-session";
    "mango-session binds to graphical-session.target" =
      cfg.systemd.user.targets.mango-session.bindsTo == [ "graphical-session.target" ];
    "mango-session target is absent without the compositor" =
      !(cfgNoDesktop.systemd.user.targets ? "mango-session");

    # Zed follows itera.desktop.theme rather than Zed's own `mode = "system"`,
    # which asks the portal and falls back to LIGHT when nothing answers.
    "zed pins the dark color scheme by default" = cfg.itera.programs.zed.settings.theme.mode == "dark";
    "zed follows theme.dark = false" = cfgLightTheme.itera.programs.zed.settings.theme.mode == "light";
    "zed sets no theme when the theme battery is off" =
      !(cfgNoTheme.itera.programs.zed.settings ? theme);

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

    # Clipboard bridge battery (default ON with the desktop): ships wl-clipboard and
    # the two always-on bridge user services. Both are load-bearing — mango does not
    # sync the X11 and Wayland selections natively, so neither direction works
    # without them. Gated off with the desktop or its toggle.
    "clipboard bridge battery is enabled" = cfg.itera.desktop.clipboard.enable;
    "wl-clipboard is installed by default" = hasPkg "wl-clipboard" cfg.environment.systemPackages;
    "clipboard wayland-to-x11 bridge service present" =
      cfg.systemd.user.services ? "itera-clipboard-wayland-to-x11";
    # The reverse direction (copy OUT of XWayland apps) must be present too — it
    # has no native XWayland fallback on mango.
    "clipboard x11-to-wayland bridge service present" =
      cfg.systemd.user.services ? "itera-clipboard-x11-to-wayland";

    # Bound to the graphical session rather than default.target. PartOf= is what
    # lets a session (or XWayland) restart cycle the daemons instead of leaving the
    # X11→Wayland loop spinning against a dead DISPLAY while looking healthy.
    "clipboard bridges are bound to the graphical session" =
      let
        unit = cfg.systemd.user.services."itera-clipboard-x11-to-wayland";
      in
      unit.partOf == [ "graphical-session.target" ]
      && unit.wantedBy == [ "graphical-session.target" ]
      && unit.after == [ "graphical-session.target" ];
    # The X11→Wayland loop exits when its display dies, so restarts must not trip
    # systemd's start rate limit.
    "clipboard bridges disable the start rate limit" =
      cfg.systemd.user.services."itera-clipboard-x11-to-wayland".startLimitIntervalSec == 0;

    # autocutsel links ONE selection to the X11 cut buffer, so select-to-copy must
    # start BOTH halves — a lone instance has nothing to link against and does
    # nothing at all (which is what the old always-on PRIMARY unit did).
    "select-to-copy is off by default" =
      !(cfg.systemd.user.services ? "itera-clipboard-autocutsel-primary")
      && !(cfg.systemd.user.services ? "itera-clipboard-autocutsel-clipboard");
    "select-to-copy starts both autocutsel halves" =
      (cfgSelectToCopy.systemd.user.services ? "itera-clipboard-autocutsel-primary")
      && (cfgSelectToCopy.systemd.user.services ? "itera-clipboard-autocutsel-clipboard");

    # Gated off: no bridge services when the battery is disabled.
    "clipboard bridge gated off when disabled" =
      !(cfgClipboardOff.systemd.user.services ? "itera-clipboard-wayland-to-x11")
      && !(cfgClipboardOff.systemd.user.services ? "itera-clipboard-x11-to-wayland")
      && !(cfgClipboardOff.systemd.user.services ? "itera-clipboard-autocutsel-primary");
  };

in
mkCheckDrv "itera-desktop-eval" checks
