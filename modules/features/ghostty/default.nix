{ ... }:
{
  flake.nixosModules.ghostty =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ghostty ];
    };
}
