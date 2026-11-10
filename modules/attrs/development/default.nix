{ self, ... }:
{
  flake.nixosModules.development = {
    imports = with self.nixosModules; [
      git
      nix-ld
      nvim
    ];
  };
}
