{ lib }:
{
  # Module discovery helpers (auto-import). Grows over time with generators,
  # custom types, etc. as the curated layer fills in.
  modules = import ./modules.nix { inherit lib; };

  # mango (MangoWC) keybind type + config.conf renderer. Not auto-discovered
  # (`listNixModules` only scans module dirs), so it is wired in by hand here.
  mango = import ./mango.nix { inherit lib; };

  # Curated-program framework: `mkCuratedProgram` declares a program's curated
  # options once and exposes them system-wide (`itera.programs.<app>`) and
  # per-user (`itera.users.<name>.programs.<app>`). See lib/programs.nix.
  programs = import ./programs.nix { inherit lib; };

  # FDE-aware installer builder: `mkInstaller pkgs { flake = "github:you/config"; }`
  # returns a package a downstream flake exposes so `nix run <flake>#installer`
  # does the whole disko-install (+ passwordless TPM2 enrollment) from a live ISO,
  # host chosen at runtime from the flake's nixosConfigurations. See lib/installer.nix.
  inherit (import ./installer.nix { inherit lib; }) mkInstaller;
}
