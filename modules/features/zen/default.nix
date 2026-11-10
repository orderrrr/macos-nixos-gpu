{ inputs, ... }:
{
  # Not in nixpkgs; the flake repackages Zen's release builds.
  flake.nixosModules.zen =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
}
