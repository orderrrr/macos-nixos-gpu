{ inputs, ... }:
{
  # `, <program>` runs anything in nixpkgs without installing it, and an unknown command says
  # which package has it. The index is prebuilt weekly, so nothing is indexed locally.
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.nixos.comma = {
    imports = [ inputs.nix-index-database.nixosModules.nix-index ];
    programs.nix-index-database.comma.enable = true;
    programs.command-not-found.enable = false; # nix-index answers instead
  };
}
