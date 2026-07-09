# itera's mango compositor battery.
#
# A thin, opinionated wrapper over the mango NixOS module (bundled by
# `modules/nixos/default.nix`). mango is a dwl-based wlroots Wayland compositor;
# enabling this turns it on and — through the upstream module — brings along the
# xdg-desktop-portal wiring (wlr + gtk), polkit, xwayland, and registers a
# `mango` wayland session with the display manager.
#
# Unlike the core-boot batteries, a desktop is NOT part of the opinionated base,
# so this gates on its OWN `enable` (`mkEnableOption`, opt-in) rather than the
# global `itera.enable` — exactly like `itera.disko`. The matching user-side
# config (autostart, keybinds) lives in the hjem battery `itera.programs.mango`.
#
# Fine-grained tuning stays reachable through the native `programs.mango.*`
# options, which remain in place because the upstream module is bundled (the same
# arrangement `itera.hardening` uses for `nix-mineral.*`).
{
  config,
  lib,
  ...
}:
let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;

  cfg = config.itera.desktop.mango;
in
{
  options.itera.desktop.mango = {
    enable = mkEnableOption "the mango Wayland compositor";
  };

  config = mkIf cfg.enable {
    programs.mango.enable = mkDefault true;
  };
}
