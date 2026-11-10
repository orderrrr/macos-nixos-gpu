{ inputs, ... }:
{
  # flake.modules.<class>.<name>: each feature file can carry its nixos and darwin sides.
  imports = [ inputs.flake-parts.flakeModules.modules ];

  # The Mac runs the VM (nix run); the guest itself is built for aarch64-linux by hosts/vm.
  systems = [ "aarch64-darwin" ];
}
