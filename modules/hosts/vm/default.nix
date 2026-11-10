{ self, inputs, ... }:
{
  flake.nixosConfigurations.vm = inputs.nixpkgs.lib.nixosSystem {
    modules = with self.nixosModules; [
      vmConfiguration
      core
      audio
      venus
      niri
      ghostty
      zen
    ];
  };

  # `nix run`: build the guest (on the nix-darwin linux-builder) and boot it in steamac's
  # launcher. Extra arguments go to steamac-vm, e.g. nix run . -- --cpus 8 --mem 16384
  #
  # The disk is made once from the build's rootfs and holds the whole system, so it only boots
  # the build it was made from. After a config change, delete it to start over (this also
  # wipes the guest's home).
  perSystem =
    { pkgs, ... }:
    let
      build = self.nixosConfigurations.vm.config.system.build;
    in
    {
      apps.default.program = pkgs.writeShellScriptBin "nixos-gpu-vm" ''
        set -eu
        bundle=${build.bundle}
        steamac=''${STEAMAC:-$HOME/opt/testing/steamac}
        state=''${XDG_DATA_HOME:-$HOME/.local/share}/nixos-gpu-vm
        disk=$state/disk.img

        if [ ! -f "$disk" ]; then
          mkdir -p "$state"
          # The rootfs (~6 GB) is only built here, so the app refers to its .drv file alone; a
          # plain drvPath would pull every output of its build closure into the app's.
          rootfs=$(nix build --no-link --print-out-paths '${builtins.unsafeDiscardOutputDependency build.rootfs.drvPath}^out')
          cp "$rootfs" "$disk"
          chmod u+w "$disk"
          truncate -s 64G "$disk" # sparse; the guest grows its filesystem on boot
          cp "$bundle/cmdline" "$disk.cmdline"
          nix store delete "$rootfs" # the copy is all we need; don't keep 6 GB in the store
        fi
        if ! cmp -s "$bundle/cmdline" "$disk.cmdline"; then
          echo "$disk was made from a different build; delete it (and with it the guest's home) to boot this one" >&2
          exit 1
        fi

        exec "$steamac/work/out/steamac-vm" \
          --kernel "$bundle/Image" \
          --initrd "$bundle/initrd" \
          --cmdline "$(cat "$bundle/cmdline")" \
          --disk "$disk" \
          --no-share \
          "$@"
      '';
    };
}
