{ inputs, config, ... }:
{
  # Not in nixpkgs; the flake repackages Zen's release builds.
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.nixos.zen =
    { pkgs, ... }:
    {
      environment.persistence."/persist".users.${config.meta.username}.directories = [ ".config/zen" ]; # the profile
      environment.systemPackages = [
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
}
