_: {
  flake.modules.nixos.btop =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.btop ];
    };
}
