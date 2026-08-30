# Evaluation check for itera's ecosystem-integration batteries: agenix secrets,
# sops-nix secrets, nix-index/comma, QEMU/KVM virtualization, the Nemo file
# manager, Secure Boot (lanzaboote), declarative Flatpak, nixos-facter, security
# keys (FIDO2/U2F), and the fingerprint reader (fprintd).
#
# Like tests/disko-impermanence-eval.nix, these are hard to VM-boot (Secure Boot
# needs enrolled keys,
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
    diskoOn
    hasPkgName
    ;

  # `diskoOn` (tests/lib.nix) turns disko + impermanence back on, so this eval
  # exercises partitioning and the tmpfs root alongside each variant's module.
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

  # Default-on batteries turned OFF, to assert their gated state: Bluetooth's
  # persisted system dir and the Vivaldi browser package.
  batteriesOff = mkEval {
    itera = {
      users.testuser = { };
      bluetooth.enable = false;
      desktop.browser.enable = false;
    };
  };
  # Same account with the batteries left on, to assert they ARE present.
  batteriesOn = mkEval { itera.users.testuser = { }; };

  # Gaming battery (opt-in, OFF by default) turns Steam on, to assert ~/.steam is
  # persisted for the account. Steam pulls in hardware.graphics.enable32Bit, which
  # nixpkgs asserts is x86_64-only, so pin the platform like the nvidia evals do so
  # this check runs identically on the aarch64 CI runner.
  gamingOn = mkConfig [
    diskoOn
    { nixpkgs.hostPlatform = lib.mkForce "x86_64-linux"; }
    {
      itera.users.testuser = { };
      itera.gaming.enable = true;
    }
  ];

  # Local-AI battery (opt-in, OFF by default) turns ollama + open-webui on, to
  # assert their state dirs are persisted. These checks only read the persisted
  # directory strings (never force the ollama/open-webui packages), so no
  # hostPlatform pin is needed — they eval identically on the aarch64 CI runner.
  aiOn = mkEval {
    itera.ai.ollama.enable = true;
    itera.ai.openWebui.enable = true;
  };

  # libvirt's default NAT network opted out, to assert the starter unit is gated.
  defaultNetworkOff = mkEval { itera.virtualisation.defaultNetwork.enable = false; };

  # File manager opted out, to assert the gvfs helpers go with it.
  fileManagerOff = mkEval { itera.desktop.fileManager.enable = false; };

  # Calculator opted out, to assert the package and its keybind command go with it.
  calculatorOff = mkEval { itera.desktop.calculator.enable = false; };

  # Video player opted out entirely, and the opt-in hardware decoding turned on,
  # to assert both gates are real: no player and no handler when off, and no
  # system mpv.conf unless something asks for one.
  videoPlayerOff = mkEval { itera.desktop.videoPlayer.enable = false; };
  videoHwdecOn = mkEval { itera.desktop.videoPlayer.hardwareDecoding = true; };

  # Fingerprint battery turned OFF, to assert its persisted state is gated.
  fingerprintOff = mkEval { itera.fingerprint.enable = false; };

  # Desktop turned OFF, to assert the lock screen's PAM service goes with it
  # rather than being left behind as an orphan stack nothing authenticates
  # against — including via the keyring battery's service list.
  desktopOff = mkEval { itera.desktop.dankMaterialShell.enable = false; };

  # sops battery (opt-in, OFF by default) merely turned ON, with no secrets
  # declared — the inert state. sops-nix gates all of its own config on
  # `sops.secrets != {}`, so this asserts itera's wiring without activating it.
  sopsOn = mkEval { itera.sops.enable = true; };

  # sops with a secret actually declared and a dedicated age key file, to assert
  # the passthrough and the impermanence wiring. sops-nix's `validateSopsFiles`
  # hashes every sopsFile at EVAL time and rejects non-sops files, so it is
  # turned off here — the check is about itera's plumbing, not about carrying a
  # real encrypted fixture (and a committed one would need a private key to be
  # useful anyway).
  sopsSecret = mkEval {
    itera.sops = {
      enable = true;
      keyFile = "/var/lib/sops-nix/key.txt";
      secrets.wifi-psk = {
        sopsFile = pkgs.writeText "secrets.yaml" "wifi-psk: ENC[dummy]";
        mode = "0400";
      };
    };
    sops.validateSopsFiles = false;
  };

  vivaldiPkg =
    cfg: lib.findFirst (p: lib.hasInfix "vivaldi" (p.name or "")) null cfg.environment.systemPackages;

  calculatorPkg =
    cfg:
    lib.findFirst (
      p: lib.hasInfix "gnome-calculator" (p.name or "")
    ) null cfg.environment.systemPackages;

  # Identity rather than a name match: the player's actual derivation name
  # (`mpv-with-scripts-<ver>`) is a nixpkgs wrapper detail this check has no
  # reason to bake in.
  hasMpv = cfg: lib.elem cfg.itera.desktop.videoPlayer.package cfg.environment.systemPackages;

  # `wsdd-` (with the dash) so this matches the wsdd package itself and not some
  # other member of the closure whose name merely contains "wsdd".
  hasWsdd = cfg: lib.any (p: lib.hasPrefix "wsdd-" (p.name or "")) cfg.environment.systemPackages;

  # facter auto-NVIDIA: feed a synthetic report directly (pure — no impure file
  # read) with a graphics_card carrying a PCI vendor id. NVIDIA is 4318 (0x10de),
  # AMD 4098 (0x1002). The battery auto-enables itera.nvidia only for NVIDIA.
  gpuReport = vendorId: { facter.report.hardware.graphics_card = [ { vendor.value = vendorId; } ]; };
  nvidiaHost = mkGpuEval (gpuReport 4318);
  amdHost = mkGpuEval (gpuReport 4098);
  # Same synthetic-report trick for the video battery's own GPU branch: Intel is
  # 32902 (0x8086), the one vendor whose VA-API driver nothing else in itera
  # installs (mesa covers AMD, itera.nvidia covers NVIDIA).
  intelHost = mkGpuEval (gpuReport 32902);
  intelHwdecOn = mkGpuEval (
    gpuReport 32902 // { itera.desktop.videoPlayer.hardwareDecoding = true; }
  );
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

  persistDirs = cfg: map (d: d.directory or d) cfg.environment.persistence."/persist".directories;
  persistFiles = cfg: map (f: f.file or f) cfg.environment.persistence."/persist".files;
  userDirs =
    cfg: name:
    map (d: d.directory or d) cfg.environment.persistence."/persist".users.${name}.directories;

  checks = {
    # --- agenix (default on, inert) ---
    "agenix identity is the persisted host key" =
      builtins.elem "/etc/ssh/ssh_host_ed25519_key" base.age.identityPaths;

    # --- sops-nix (opt-in, OFF by default) ---
    # agenix stays the default engine, so a default host gets no sops wiring at
    # all. sops-nix's own sshKeyPaths default derives from services.openssh
    # (off in itera core), so an empty list here really means "itera wired
    # nothing" rather than "upstream defaulted to nothing visible".
    "sops is off by default" = !base.itera.sops.enable;
    "sops CLI is not installed by default" = !hasPkgName "sops" base.environment.systemPackages;
    "sops age identity is unwired by default" = base.sops.age.sshKeyPaths == [ ];
    # Turned on but inert: identity and CLI are wired, no secrets are declared.
    "sops age identity is the persisted host key when on" =
      builtins.elem "/etc/ssh/ssh_host_ed25519_key" sopsOn.sops.age.sshKeyPaths;
    "sops declares no secrets when merely enabled" = sopsOn.sops.secrets == { };
    "sops default format is yaml" = sopsOn.sops.defaultSopsFormat == "yaml";
    "sops CLI is installed when on" = hasPkgName "sops" sopsOn.environment.systemPackages;
    "ssh-to-age is installed when on" = hasPkgName "ssh-to-age" sopsOn.environment.systemPackages;
    # itera pins the engine to age; upstream would otherwise adopt the host RSA
    # key as a second, GnuPG decryption path whenever openssh is on.
    "sops stays age-only (no GnuPG identity)" = sopsOn.sops.gnupg.sshKeyPaths == [ ];
    # The two engines are independent: enabling sops leaves agenix fully wired.
    "agenix is untouched when sops is enabled" =
      builtins.elem "/etc/ssh/ssh_host_ed25519_key" sopsOn.age.identityPaths;
    # A declared secret reaches the native option tree untouched.
    "sops secret passes through to sops.secrets" = sopsSecret.sops.secrets ? wifi-psk;
    "sops secret keeps its declared mode" = sopsSecret.sops.secrets.wifi-psk.mode == "0400";
    # ...and actually activates: sops-nix installs secrets from an activation
    # script, decrypting to the /run tmpfs. This is the pair that proves "inert
    # until used" is real rather than merely unasserted — no script with the
    # battery merely on, a script once a secret exists.
    "sops installs nothing while inert" = !(sopsOn.system.activationScripts ? setupSecrets);
    "sops installs secrets once one is declared" = sopsSecret.system.activationScripts ? setupSecrets;
    "sops secret decrypts to the /run tmpfs" =
      sopsSecret.sops.secrets.wifi-psk.path == "/run/secrets/wifi-psk";
    # A dedicated age key file lives outside the store, so the ephemeral root
    # would eat it; itera.impermanence persists it, but only when it is in use.
    "sops key file is wired when set" = sopsSecret.sops.age.keyFile == "/var/lib/sops-nix/key.txt";
    "sops key file is persisted when set" = builtins.elem "/var/lib/sops-nix/key.txt" (
      persistFiles sopsSecret
    );
    "sops key file is not persisted when unused" =
      !lib.any (f: lib.hasInfix "sops-nix" f) (persistFiles base);

    # --- nix-index + comma (default on) ---
    "nix-index is enabled" = base.programs.nix-index.enable;
    "comma is enabled" = base.programs.nix-index-database.comma.enable;

    # --- virtualisation (default on) ---
    "libvirtd is enabled" = base.virtualisation.libvirtd.enable;
    "virt-manager GUI is enabled" = base.programs.virt-manager.enable;
    "swtpm is enabled for guests" = base.virtualisation.libvirtd.qemu.swtpm.enable;
    "libvirt state is persisted" = builtins.elem "/var/lib/libvirt" (persistDirs base);
    # The `default` NAT network is defined by upstream but left inactive, so itera
    # starts + autostarts it at boot. Present by default, gone when opted out.
    "default network unit is pulled in at boot" =
      builtins.elem "multi-user.target" base.systemd.services.itera-libvirt-default-network.wantedBy;
    "default network unit starts it after libvirtd" =
      builtins.elem "libvirtd.service" base.systemd.services.itera-libvirt-default-network.after;
    "default network unit is dropped when opted out" =
      !(defaultNetworkOff.systemd.services ? itera-libvirt-default-network);

    # --- Nemo file manager (default on) ---
    "gvfs is enabled" = base.services.gvfs.enable;
    "tumbler thumbnails are enabled" = base.services.tumbler.enable;
    "nemo is the default directory handler" =
      base.xdg.mime.defaultApplications."inode/directory" == "nemo.desktop";
    # gvfs' WS-Discovery backend automounts but spawns `wsdd` off PATH, so the
    # binary has to be installed or Nemo's "Network" finds no SMB hosts.
    "wsdd is installed for gvfs network discovery" = hasWsdd base;
    "wsdd is dropped with the file manager" = !hasWsdd fileManagerOff;
    # Client-side discovery only: itera must not stand up the wsdd *responder*,
    # which would advertise this host on the LAN.
    "wsdd responder is not enabled" = !base.services.samba-wsdd.enable;

    # --- Vivaldi browser (default on) ---
    "vivaldi is the default https handler" =
      base.xdg.mime.defaultApplications."x-scheme-handler/https" == "vivaldi-stable.desktop";
    "browser keybind command is wired" = base.itera.desktop.mango.commands.browser == "vivaldi";
    # The Vivaldi package is installed while the battery is on and dropped with it.
    "vivaldi installed when browser on" = vivaldiPkg batteriesOn != null;
    "vivaldi not installed when browser off" = vivaldiPkg batteriesOff == null;
    # Vivaldi's profile lives at ~/.config/vivaldi, covered by the curated `.config`
    # home dir (persisted unconditionally), so no browser-gated persistence entry.

    # --- GNOME Calculator (default on) ---
    "calculator keybind command is wired" =
      base.itera.desktop.mango.commands.calculator == "gnome-calculator";
    "gnome-calculator installed when calculator on" = calculatorPkg base != null;
    "gnome-calculator not installed when calculator off" = calculatorPkg calculatorOff == null;
    # Opting out must also clear the spawn command, or the compositor keeps a bind
    # pointing at a binary that is no longer on PATH.
    "calculator keybind command cleared when off" =
      calculatorOff.itera.desktop.mango.commands.calculator == null;
    # History and preferences live in ~/.config/dconf, covered by the curated
    # `.config` home dir, so no calculator-gated persistence entry either.

    # --- mpv video player (default on) ---
    "mpv installed when the video player is on" = hasMpv base;
    "mpv not installed when the video player is off" = !hasMpv videoPlayerOff;
    "mpv is the default video/mp4 handler" =
      base.xdg.mime.defaultApplications."video/mp4" == "mpv.desktop";
    # The handler must go with the package. Leaving it behind points the session
    # at a `.desktop` id no installed package provides, and opening a video then
    # fails with no visible reason.
    "no video handler when the video player is off" =
      !(videoPlayerOff.xdg.mime.defaultApplications ? "video/mp4");

    # `package = null` is for bringing your own mpv build, so it must drop the
    # package while KEEPING the handler wiring — the opposite of opting the
    # battery out. (An identity check on a null package would pass vacuously, so
    # this asserts the handler, which is the part with something to get wrong.)
    "handler survives dropping the player package" =
      (mkEval { itera.desktop.videoPlayer.package = null; }).xdg.mime.defaultApplications."video/mp4"
      == "mpv.desktop";

    # Hardware decoding is opt-in, and its OFF state must leave no file at all
    # rather than an empty one: mpv reads /etc/mpv/mpv.conf before the user's own,
    # so anything orphaned here is a default every user on the host inherits.
    "no system mpv.conf by default" = !(base.environment.etc ? "mpv/mpv.conf");
    "no system mpv.conf when the video player is off" =
      !(videoPlayerOff.environment.etc ? "mpv/mpv.conf");
    "opting in writes hwdec into the system mpv.conf" =
      lib.hasInfix "hwdec=auto"
        videoHwdecOn.environment.etc."mpv/mpv.conf".text;
    # settings is per-key overridable rather than all-or-nothing: pinning a
    # known-good method for a host must win over the switch's own default.
    "settings.hwdec overrides the opt-in default" =
      lib.hasInfix "hwdec=vaapi"
        (mkEval {
          itera.desktop.videoPlayer.hardwareDecoding = true;
          itera.desktop.videoPlayer.settings.hwdec = "vaapi";
        }).environment.etc."mpv/mpv.conf".text;

    # Intel is the one vendor whose VA-API driver nothing else installs, so
    # hardware decoding there is only real if the battery supplies it. It follows
    # the opt-in switch (no driver dragged in for a feature nobody asked for),
    # must NOT be handed to hosts that don't need it, and must survive alongside
    # the NVIDIA module's own (normal-priority) extraPackages on a hybrid laptop.
    "intel VA-API driver added on an Intel host that opted in" =
      hasPkgName "intel-media-driver" intelHwdecOn.hardware.graphics.extraPackages;
    "no intel VA-API driver until hardware decoding is asked for" =
      !hasPkgName "intel-media-driver" intelHost.hardware.graphics.extraPackages;
    "no intel VA-API driver on an AMD host" =
      !hasPkgName "intel-media-driver" amdHost.hardware.graphics.extraPackages;
    "intel VA-API driver survives the nvidia module's extraPackages" =
      hasPkgName "intel-media-driver"
        (mkGpuEval (
          gpuReport 32902
          // {
            itera.nvidia.enable = true;
            itera.desktop.videoPlayer.hardwareDecoding = true;
          }
        )).hardware.graphics.extraPackages;
    # mpv's own state (watch-later, ~/.config/mpv) lives in the curated `.config`
    # / `.local/state` home dirs, so there is no video-gated persistence entry.

    # --- Steam / gaming (opt-in): ~/.steam persisted, gated on Steam being on ---
    # The library, Proton prefixes and cloud saves live under ~/.local/share/Steam
    # (persisted via the curated `.local/share`); ~/.steam is a top-level dotdir
    # (registry.vdf: auto-login user, language) that must be added/removed with
    # Steam itself, so it is persisted only while the battery is on.
    "steam dir persisted when gaming on" = builtins.elem ".steam" (userDirs gamingOn "testuser");
    "steam dir not persisted when gaming off" =
      !builtins.elem ".steam" (userDirs batteriesOn "testuser");

    # --- Local AI (opt-in): ollama/open-webui state persisted, gated on the services ---
    # Both run as DynamicUser services, so their real StateDirectory data lives at
    # /var/lib/private/<name>; persist those so pulled models and the web UI's
    # accounts/settings/chats survive the wiped root. AI is off in `base`, the gated-off
    # case.
    "ollama state persisted when on" = builtins.elem "/var/lib/private/ollama" (persistDirs aiOn);
    "ollama state not persisted when off" = !builtins.elem "/var/lib/private/ollama" (persistDirs base);
    "open-webui state persisted when on" = builtins.elem "/var/lib/private/open-webui" (
      persistDirs aiOn
    );
    "open-webui state not persisted when off" =
      !builtins.elem "/var/lib/private/open-webui" (persistDirs base);

    # --- Bluetooth (default on): pairings persisted, gated on the battery ---
    "bluetooth pairings persisted when on" = builtins.elem "/var/lib/bluetooth" (persistDirs base);
    "bluetooth pairings not persisted when off" =
      !builtins.elem "/var/lib/bluetooth" (persistDirs batteriesOff);

    # --- dark mode by default ---
    "GTK apps default to dark" = base.environment.sessionVariables.GTK_THEME == "Adwaita:dark";
    "DMS shell defaults to dark (portal sync off)" =
      base.itera.programs.dankMaterialShell.settings.syncModeWithPortal == false;
    # Zed reads neither GTK_THEME nor dconf, so it needs its own pinned mode —
    # otherwise it asks the portal and falls back to light when none answers.
    "Zed defaults to dark" = base.itera.programs.zed.settings.theme.mode == "dark";

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
    # The FIDO2 CLI (fido2-token/-cred/-assert) — udev.packages above only pulls in
    # libfido2's rules, so the package has to be installed separately to get binaries.
    "libfido2 CLI is installed by default" = lib.any (
      p: lib.hasInfix "libfido2" (p.name or "")
    ) base.environment.systemPackages;
    # Like fingerprint: the key is explicitly OFF on the initial-login surfaces...
    "security key is disabled at TTY login" = base.security.pam.services.login.u2f.enable == false;
    "security key is disabled at the greeter" = base.security.pam.services.greetd.u2f.enable == false;
    # ...but ON for in-session privilege prompts (pam_u2f's default from the global).
    "security key is enabled for sudo" = base.security.pam.services.sudo.u2f.enable == true;
    "security key is enabled for polkit" = base.security.pam.services.polkit-1.u2f.enable == true;
    # DMS lock screen accepts the key (key OR password).
    "DMS lock screen enables u2f" = base.itera.programs.dankMaterialShell.settings.enableU2f == true;
    "DMS lock screen u2f mode is 'or' by default" =
      base.itera.programs.dankMaterialShell.settings.u2fMode == "or";
    # The greeter's key-auth UI settings.json is still wired (it now carries
    # greeterEnableU2f = false, since the greeter is a login surface).
    "greeter u2f config file is wired" = base.programs.dms-greeter.configFiles != [ ];

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
    # fprintd is kept resident, so its idle exit cannot race the lock screen's
    # fingerprint attempt. The empty first entry is the systemd reset that has to
    # precede overriding an ExecStart inherited from the packaged unit.
    "fprintd ExecStart is reset before being overridden" =
      builtins.elem "" base.systemd.services.fprintd.serviceConfig.ExecStart;
    "fprintd runs with --no-timeout" = lib.any (
      c: lib.hasSuffix "/libexec/fprintd --no-timeout" c
    ) base.systemd.services.fprintd.serviceConfig.ExecStart;
    # Opting out of the battery leaves the packaged unit untouched.
    "fprintd ExecStart is not overridden when off" =
      !(fingerprintOff.systemd.services ? fprintd)
      || !(fingerprintOff.systemd.services.fprintd.serviceConfig ? ExecStart);
    # --- The DMS lock screen's own PAM service (`/etc/pam.d/dankshell`) ---
    # Declared, so DMS stops generating one imperatively into persisted user state.
    "lock screen PAM service exists" = base.security.pam.services ? dankshell;
    "lock screen PAM service authenticates" = base.security.pam.services.dankshell.unixAuth;
    # An unlock is not a login: no second session registered, no tty vetting.
    "lock screen PAM service starts no session" =
      base.security.pam.services.dankshell.startSession == false;
    "lock screen PAM service sets no login uid" =
      base.security.pam.services.dankshell.setLoginUid == false;
    "lock screen PAM stack has no pam_securetty" =
      !lib.hasInfix "pam_securetty" base.security.pam.services.dankshell.text;
    # Both second factors are DMS's own PAM contexts, so they must NOT also be
    # inline here — that would double-prompt. These are the assertions that would
    # catch nixpkgs' fprintd/u2f defaults leaking back in.
    "lock screen PAM stack has no inline pam_fprintd" =
      base.security.pam.services.dankshell.fprintAuth == false
      && !lib.hasInfix "pam_fprintd" base.security.pam.services.dankshell.text;
    "lock screen PAM stack has no inline pam_u2f" =
      base.security.pam.services.dankshell.u2f.enable == false
      && !lib.hasInfix "pam_u2f" base.security.pam.services.dankshell.text;
    # ...but the keyring IS unlocked from it, so re-authenticating at the lock
    # screen unlocks a keyring that got locked in the meantime.
    "lock screen unlocks the keyring" = base.security.pam.services.dankshell.enableGnomeKeyring == true;
    "keyring lists the lock screen service" = builtins.elem "dankshell" base.itera.keyring.pamServices;
    # Dropping the desktop drops the service — no orphan stack, and the keyring
    # battery must not conjure one back via its service list.
    "lock screen PAM service is gone without the desktop" =
      !(desktopOff.security.pam.services ? dankshell);
    "keyring does not list the lock screen service without the desktop" =
      !builtins.elem "dankshell" desktopOff.itera.keyring.pamServices;
    # Enrolled prints are persisted across the tmpfs root, gated on the battery.
    "fprint enrollments are persisted when on" = builtins.elem "/var/lib/fprint" (persistDirs base);
    "fprint enrollments are not persisted when off" =
      !builtins.elem "/var/lib/fprint" (persistDirs fingerprintOff);
  };

in
mkCheckDrv "itera-integrations-eval" checks
