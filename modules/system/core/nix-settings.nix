{ config, ... }:
{
  flake.modules.nixos.nix = {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          config.meta.username
        ];
      };
      # Each in-guest rebuild keeps its generation, and the disk file on the Mac only grows.
      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-older-than 5d";
      };
      optimise.automatic = true;
    };
  };
}
