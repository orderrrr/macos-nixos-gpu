{ config, ... }:
{
  flake.modules.nixos.development = {
    imports = with config.flake.modules.nixos; [
      git
      nix-ld
      nvim
      direnv
      comma
      mangohud
    ];
  };
}
