{ config, ... }:
{
  flake.modules.nixos.core = {
    imports = with config.flake.modules.nixos; [
      bootloader
      user
      nix
      locale
    ];
    system.stateVersion = "26.11";
  };
}
