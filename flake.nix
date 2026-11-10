{
  description = "NixOS aarch64 guest with Venus GPU, booted by steamac's libkrun launcher on Apple silicon";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6"; # nixos-unstable 2026-11-07

  outputs =
    { nixpkgs, ... }:
    let
      vm = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [ ./configuration.nix ];
      };
    in
    {
      nixosConfigurations.vm = vm;
      # Built on the nix-darwin linux-builder; run.sh boots it. The rootfs (~6 GB) is only
      # built to make disk.img, so it is kept apart from the small boot bundle.
      packages.aarch64-darwin.bundle = vm.config.system.build.bundle;
      packages.aarch64-darwin.rootfs = vm.config.system.build.rootfs;
    };
}
