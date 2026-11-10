{ inputs, ... }:
{
  # flake.nix is generated from the flake-file options in these modules: each feature declares
  # the inputs it uses. After changing any, run `nix run .#write-flake`; `nix flake check`
  # fails while flake.nix is stale.
  imports = [ inputs.flake-file.flakeModules.default ];

  flake-file = {
    description = "NixOS aarch64 guest with Venus GPU, booted by steamac's libkrun launcher on Apple silicon";
    outputs = "dendritic"; # mkFlake over import-tree ./modules
    inputs = {
      flake-file.url = "github:denful/flake-file";
      flake-parts.url = "github:hercules-ci/flake-parts";
      import-tree.url = "github:vic/import-tree";
      nixpkgs.url = "github:NixOS/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6"; # nixos-unstable 2026-11-07
    };
  };
}
