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
}
