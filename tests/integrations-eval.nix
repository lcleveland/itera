# Evaluation check for itera's ecosystem-integration batteries: agenix secrets,
# nix-index/comma, QEMU/KVM virtualization, the Nemo file manager, Secure Boot
# (lanzaboote), declarative Flatpak, nixos-facter, security keys (FIDO2/U2F), and
# the fingerprint reader (fprintd).
#
# Like tests/eval.nix, these are hard to VM-boot (Secure Boot needs enrolled keys,
# libvirt/flatpak pull services) so we evaluate two NixOS configurations — one at
# defaults, one with the opt-in batteries turned on — and assert the generated
# config. `nix build` forces evaluation and fails loudly on any false assertion.
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

  # This check exercises impermanence persistence, so turn disko + impermanence
  # on (overriding mkConfig's defaults) alongside each variant's extra module.
  diskoOn = {
    itera.disko = {
      enable = true;
      device = "/dev/vda";
    };
    itera.impermanence.enable = true;
  };
  mkEval =
    extra:
    mkConfig [
      diskoOn
      extra
    ];

  # itera.nvidia is x86_64-only: enabling it sets hardware.graphics.enable32Bit,
  # which nixpkgs asserts is "only supported on an x86_64 system". mkConfig builds
  # each config with the discovering system (tests/lib.nix), so on the aarch64 CI
  # runner the nvidia configs would trip that platform assertion. Pin the nvidia /
  # GPU-detection configs to x86_64 (mkForce overrides mkConfig's system) so these
  # checks exercise the real, x86_64-only nvidia behavior identically on both
  # runners rather than failing on aarch64.
  mkGpuEval =
    extra:
    mkConfig [
      diskoOn
      { nixpkgs.hostPlatform = lib.mkForce "x86_64-linux"; }
      extra
    ];

  # Defaults: opt-out batteries on, opt-in batteries off.
  base = mkEval { };

  # Opt-in batteries turned on (Secure Boot + Flatpak).
  optIn = mkEval {
    itera.secureBoot.enable = true;
    itera.desktop.flatpak.enable = true;
  };

  # Default-on batteries turned OFF, to assert their persisted state is gated:
  # Bluetooth (system dir) and the LibreWolf profile (per-user home dir).
  batteriesOff = mkEval {
    itera = {
      users.testuser = { };
      bluetooth.enable = false;
      desktop.browser.enable = false;
    };
  };
  # Same account with the batteries left on, to assert the profile IS persisted.
  batteriesOn = mkEval { itera.users.testuser = { }; };

  # Fingerprint battery turned OFF, to assert its persisted state is gated.
  fingerprintOff = mkEval { itera.fingerprint.enable = false; };

  # Browser with Firefox Sync opted out, to assert the extraPrefs override is
  # actually applied to the packaged LibreWolf (it changes the derivation).
  syncOff = mkEval { itera.desktop.browser.enableSync = false; };
  librewolfPkg =
    cfg: lib.findFirst (p: lib.hasInfix "librewolf" (p.name or "")) null cfg.environment.systemPackages;

  # facter auto-NVIDIA: feed a synthetic report directly (pure — no impure file
  # read) with a graphics_card carrying a PCI vendor id. NVIDIA is 4318 (0x10de),
  # AMD 4098 (0x1002). The battery auto-enables itera.nvidia only for NVIDIA.
  gpuReport = vendorId: { facter.report.hardware.graphics_card = [ { vendor.value = vendorId; } ]; };
  nvidiaHost = mkGpuEval (gpuReport 4318);
  amdHost = mkGpuEval (gpuReport 4098);
  nvidiaOptOut = mkGpuEval (gpuReport 4318 // { itera.hardware.facter.autoNvidia = false; });

  # nvidia-container-toolkit driver-assertion defusing: force the toolkit on while
  # itera.nvidia stays off (no driver, no "nvidia" in videoDrivers), the state that
  # made the upstream assertion abort a rebuild. itera should suppress it + warn so
  # evaluation still succeeds.
  toolkitNoDriver = mkEval { hardware.nvidia-container-toolkit.enable = true; };

  # Regression (the reported bug): itera.nvidia is ON, but the consumer (or an
  # imported hardware profile) defines services.xserver.videoDrivers at NORMAL
  # priority. itera contributes "nvidia" ADDITIVELY (a plain list), so it must MERGE
  # rather than be clobbered — keeping "nvidia" present and satisfying the upstream
  # assertion the real way (no suppression needed).
  nvidiaVideoDriversMerged = mkGpuEval {
    itera.nvidia.enable = true;
    services.xserver.videoDrivers = [ "modesetting" ];
  };

  # The edge the broadened suppression net still covers: itera.nvidia ON but a
  # consumer mkForce drops "nvidia" from videoDrivers. itera can't win the merge,
  # so it suppresses the upstream assertion + warns instead of aborting.
  nvidiaVideoDriversForced = mkGpuEval {
    itera.nvidia.enable = true;
    services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
  };

  # LibreWolf keepLogins off, to assert the extraPrefs override rebuilds the package.
  keepLoginsOff = mkEval { itera.desktop.browser.keepLogins = false; };

  persistDirs = cfg: map (d: d.directory or d) cfg.environment.persistence."/persist".directories;
  userDirs =
    cfg: name:
    map (d: d.directory or d) cfg.environment.persistence."/persist".users.${name}.directories;

  checks = {
    # --- agenix (default on, inert) ---
    "agenix identity is the persisted host key" =
      builtins.elem "/etc/ssh/ssh_host_ed25519_key" base.age.identityPaths;

    # --- nix-index + comma (default on) ---
    "nix-index is enabled" = base.programs.nix-index.enable;
    "comma is enabled" = base.programs.nix-index-database.comma.enable;

    # --- virtualisation (default on) ---
    "libvirtd is enabled" = base.virtualisation.libvirtd.enable;
    "virt-manager GUI is enabled" = base.programs.virt-manager.enable;
    "swtpm is enabled for guests" = base.virtualisation.libvirtd.qemu.swtpm.enable;
    "libvirt state is persisted" = builtins.elem "/var/lib/libvirt" (persistDirs base);

    # --- Nemo file manager (default on) ---
    "gvfs is enabled" = base.services.gvfs.enable;
    "tumbler thumbnails are enabled" = base.services.tumbler.enable;
    "nemo is the default directory handler" =
      base.xdg.mime.defaultApplications."inode/directory" == "nemo.desktop";

    # --- LibreWolf browser (default on) ---
    "librewolf is the default https handler" =
      base.xdg.mime.defaultApplications."x-scheme-handler/https" == "librewolf.desktop";
    "browser keybind command is wired" = base.itera.desktop.mango.commands.browser == "librewolf";
    # The ~/.librewolf profile is persisted while the battery is on, and gated off
    # with it (it lives outside the curated home dirs, so it must be added/removed
    # with the browser rather than persisted unconditionally).
    "librewolf profile persisted when browser on" = builtins.elem ".librewolf" (
      userDirs batteriesOn "testuser"
    );
    "librewolf profile not persisted when browser off" =
      !builtins.elem ".librewolf" (userDirs batteriesOff "testuser");
    # Firefox Sync is enabled by default and its extraPrefs override actually
    # rebuilds LibreWolf (turning it off yields a different derivation).
    "firefox sync enabled by default" = base.itera.desktop.browser.enableSync;
    "enabling sync overrides the librewolf derivation" =
      (librewolfPkg base).drvPath != (librewolfPkg syncOff).drvPath;
    # keepLogins is on by default (logins survive a restart despite LibreWolf's
    # clear-on-shutdown), and toggling it rebuilds the package via extraPrefs.
    "browser keepLogins on by default" = base.itera.desktop.browser.keepLogins;
    "disabling keepLogins overrides the librewolf derivation" =
      (librewolfPkg base).drvPath != (librewolfPkg keepLoginsOff).drvPath;

    # --- Bluetooth (default on): pairings persisted, gated on the battery ---
    "bluetooth pairings persisted when on" = builtins.elem "/var/lib/bluetooth" (persistDirs base);
    "bluetooth pairings not persisted when off" =
      !builtins.elem "/var/lib/bluetooth" (persistDirs batteriesOff);

    # --- dark mode by default ---
    "GTK apps default to dark" = base.environment.sessionVariables.GTK_THEME == "Adwaita:dark";
    "DMS shell defaults to dark (portal sync off)" =
      base.itera.programs.dankMaterialShell.settings.syncModeWithPortal == false;

    # --- Secure Boot (default OFF, so systemd-boot stays) ---
    "lanzaboote is off by default" = !base.boot.lanzaboote.enable;
    "systemd-boot is on by default" = base.boot.loader.systemd-boot.enable;

    # --- Flatpak (default OFF) ---
    "flatpak is off by default" = !base.services.flatpak.enable;

    # --- facter (default: auto-generate a host-local report) ---
    # Auto-generation is on by default and points at a persisted host-local path.
    "facter autoGenerate is on by default" = base.itera.hardware.facter.autoGenerate;
    "facter reportPath defaults to the host-local path" =
      base.itera.hardware.facter.reportPath == "/var/lib/itera/facter.json";
    # In a PURE eval, the absolute report path is not present (pathExists is false
    # for absolute paths in pure mode), so the report stays unwired and detection
    # falls back to the curated module list — no impure read, no failure.
    "facter reportPath is unwired when the report is absent" = base.facter.reportPath == null;
    # The auto-generated report's directory is persisted across the tmpfs root.
    "facter report dir is persisted" = builtins.elem "/var/lib/itera" (persistDirs base);

    # --- facter auto-NVIDIA (default on) ---
    "an NVIDIA GPU auto-enables itera.nvidia" = nvidiaHost.itera.nvidia.enable;
    "a non-NVIDIA GPU leaves itera.nvidia off" = !amdHost.itera.nvidia.enable;
    "no report leaves itera.nvidia off" = !base.itera.nvidia.enable;
    "autoNvidia = false is honored with an NVIDIA GPU present" = !nvidiaOptOut.itera.nvidia.enable;

    # --- nvidia-container-toolkit driver-assertion defusing ---
    # Toolkit on without a driver: itera suppresses the upstream assertion, warns,
    # and the config still evaluates (no failed assertion aborts `itera update`).
    "toolkit without a driver suppresses the upstream assertion" =
      toolkitNoDriver.hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion == true;
    "toolkit without a driver warns" = lib.any (
      w: lib.hasInfix "NVIDIA container toolkit is enabled" w
    ) toolkitNoDriver.warnings;
    "toolkit without a driver still evaluates with no failed assertion" =
      builtins.filter (a: !a.assertion) toolkitNoDriver.assertions == [ ];
    # The healthy facter-driven path is unaffected: driver in videoDrivers, no
    # suppression (the upstream assertion is satisfied the real way).
    "facter-driven nvidia keeps nvidia in videoDrivers" =
      builtins.elem "nvidia" nvidiaHost.services.xserver.videoDrivers;
    "facter-driven nvidia does not suppress the assertion" =
      nvidiaHost.hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion == false;

    # Reported bug: itera.nvidia ON + a normal-priority consumer/profile videoDrivers
    # def MERGES with itera's additive "nvidia" (rather than clobbering it), so the
    # driver stays present, the assertion is satisfied the real way (no suppression),
    # and evaluation succeeds with no failed assertion.
    "battery-on merges nvidia with a consumer videoDrivers def" =
      builtins.elem "nvidia" nvidiaVideoDriversMerged.services.xserver.videoDrivers
      && builtins.elem "modesetting" nvidiaVideoDriversMerged.services.xserver.videoDrivers;
    "battery-on with a consumer videoDrivers def needs no suppression" =
      nvidiaVideoDriversMerged.hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion == false;
    "battery-on with a consumer videoDrivers def still evaluates cleanly" =
      builtins.filter (a: !a.assertion) nvidiaVideoDriversMerged.assertions == [ ];

    # Safety net: itera.nvidia ON but a consumer mkForce drops "nvidia" — itera can't
    # win the merge, so it suppresses the upstream assertion + warns instead of
    # aborting, and evaluation still succeeds.
    "battery-on with a forced videoDrivers override suppresses the assertion" =
      nvidiaVideoDriversForced.hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion == true;
    "battery-on with a forced videoDrivers override still evaluates with no failed assertion" =
      builtins.filter (a: !a.assertion) nvidiaVideoDriversForced.assertions == [ ];

    # --- Secure Boot opt-in: swaps bootloader + persists keys ---
    "lanzaboote turns on when opted in" = optIn.boot.lanzaboote.enable;
    "systemd-boot is forced off under Secure Boot" = !optIn.boot.loader.systemd-boot.enable;
    "Secure Boot keys are persisted when opted in" = builtins.elem "/var/lib/sbctl" (persistDirs optIn);

    # --- Flatpak opt-in: enables service + persists installs ---
    "flatpak turns on when opted in" = optIn.services.flatpak.enable;
    "flatpak state is persisted when opted in" = builtins.elem "/var/lib/flatpak" (persistDirs optIn);

    # --- Security keys (FIDO2/U2F, default on) ---
    "pam u2f is enabled by default" = base.security.pam.u2f.enable;
    # Default control is "sufficient" = key OR password (no lockout without a key).
    "pam u2f control is key-OR-password by default" = base.security.pam.u2f.control == "sufficient";
    "pcscd smartcard daemon is enabled by default" = base.services.pcscd.enable;
    # Device udev rules for FIDO2 (libfido2) and YubiKey (yubikey-personalization).
    "security-key udev packages are wired" =
      lib.any (p: lib.hasInfix "libfido2" (p.name or "")) base.services.udev.packages
      && lib.any (p: lib.hasInfix "yubikey-personalization" (p.name or "")) base.services.udev.packages;
    "ykman is installed by default" = lib.any (
      p: lib.hasInfix "yubikey-manager" (p.name or "")
    ) base.environment.systemPackages;
    # DMS lock screen accepts the key (key OR password).
    "DMS lock screen enables u2f" = base.itera.programs.dankMaterialShell.settings.enableU2f == true;
    "DMS lock screen u2f mode is 'or' by default" =
      base.itera.programs.dankMaterialShell.settings.u2fMode == "or";
    # The greeter's key-auth UI is wired (a greeter settings.json is supplied).
    "greeter u2f config file is wired" = base.programs.dank-material-shell.greeter.configFiles != [ ];

    # --- Fingerprint (default on): after-login only, never initial login ---
    "fprintd is enabled by default" = base.services.fprintd.enable;
    # Fingerprint is explicitly OFF on the initial-login surfaces...
    "fingerprint is disabled at TTY login" = base.security.pam.services.login.fprintAuth == false;
    "fingerprint is disabled at the greeter" = base.security.pam.services.greetd.fprintAuth == false;
    # ...but ON for in-session privilege prompts (fprintd's default).
    "fingerprint is enabled for sudo" = base.security.pam.services.sudo.fprintAuth == true;
    "fingerprint is enabled for polkit" = base.security.pam.services.polkit-1.fprintAuth == true;
    # DMS lock screen offers fingerprint unlock.
    "DMS lock screen enables fingerprint" =
      base.itera.programs.dankMaterialShell.settings.enableFprint == true;
    # Enrolled prints are persisted across the tmpfs root, gated on the battery.
    "fprint enrollments are persisted when on" = builtins.elem "/var/lib/fprint" (persistDirs base);
    "fprint enrollments are not persisted when off" =
      !builtins.elem "/var/lib/fprint" (persistDirs fingerprintOff);
  };

in
mkCheckDrv "itera-integrations-eval" checks
