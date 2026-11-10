{ self, ... }:
{
  flake.nixosModules.core = {
    imports = with self.nixosModules; [
      bootloader
      user
      nix
    ];
    system.stateVersion = "26.11";
  };
}
