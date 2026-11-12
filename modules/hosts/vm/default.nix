{
  self,
  inputs,
  config,
  ...
}:
{
  flake.nixosConfigurations.vm = inputs.nixpkgs.lib.nixosSystem {
    modules = with config.flake.modules.nixos; [
      vmConfiguration
      core
      audio
      venus
      cursor
      darkMode
      niri
      noctalia
      steamac-agent
      omacvm
      omacvm-battery
      omacvm-camera
      omacvm-gestures
      omacvm-notch
      omacvm-touchid
      mac-share
      ghostty
      btop
      zen
      development
      impermanence
    ];
  };

  # `nix run`: boot the guest in steamac's launcher, sharing ~/VM (this repo, hidden as
  # ~/VM/.nixos-gpu-vm, and anything else you put there; features/mac-share).
  # Extra arguments go to steamac-vm, e.g. nix run . -- --cpus 8 --mem 16384
  # The mouse is captured while the window is in front, so the guest cursor also reaches the
  # strip beside the notch (Ctrl+Option releases it; launcher patch 0004).
  #
  # The disk is made once (from a rootfs built on the nix-darwin linux-builder) and kept; the
  # guest changes itself with `sudo nixos-rebuild switch --flake /etc/nixos#vm` like any NixOS.
  # Only the kernel and initrd come from here on each run.
  perSystem =
    { pkgs, ... }:
    let
      build = self.nixosConfigurations.vm.config.system.build;
    in
    {
      apps.default.program = pkgs.writeShellScriptBin "nixos-gpu-vm" ''
        set -eu
        bundle=${build.bundle}
        share=''${NIXOS_GPU_VM_SHARE:-$HOME/VM}
        state=''${XDG_DATA_HOME:-$HOME/.local/share}/nixos-gpu-vm
        steamac=$state/steamac # fetched and built by build.sh
        disk=$state/disk.img

        mkdir -p "$state"
        # Keep the kernel and initrd through garbage collection: the patched kernel takes ~30 min.
        nix-store --add-root "$state/bundle" --realise "$bundle" > /dev/null

        if [ ! -f "$disk" ]; then
          # The rootfs (~6 GB) is only built here, so the app refers to its .drv file alone; a
          # plain drvPath would pull every output of its build closure into the app's.
          rootfs=$(nix build --no-link --print-out-paths '${builtins.unsafeDiscardOutputDependency build.rootfs.drvPath}^out')
          cp "$rootfs" "$disk"
          chmod u+w "$disk"
          truncate -s 64G "$disk" # sparse; the guest grows its filesystem on boot
          nix store delete "$rootfs" # the copy is all we need; don't keep 6 GB in the store
        fi

        exec "$steamac/work/out/steamac-vm" \
          --kernel "$bundle/Image" \
          --initrd "$bundle/initrd" \
          --cmdline "$(cat "$bundle/cmdline")" \
          --disk "$disk" \
          --share "$share" \
          --no-share-library \
          --mouse capture \
          "$@"
      '';
    };
}
