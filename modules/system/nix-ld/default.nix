{ ... }:
{
  # Prebuilt Linux binaries (language servers editors download, vendor toolchains) expect a
  # standard loader and libc, which NixOS doesn't have; nix-ld provides them.
  flake.modules.nixos.nix-ld =
    { pkgs, ... }:
    {
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc
          util-linux
          zlib
        ];
      };
    };
}
