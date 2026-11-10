{ self, ... }:
{
  flake.nixosModules.core = {
    imports = with self.nixosModules; [
      bootloader
      user
      nix
      locale
    ];
    system.stateVersion = "26.11";
  };
}
