{ ... }:
{
  flake.nixosModules.bootloader =
    { pkgs, ... }:
    {
      boot.kernelPackages = pkgs.linuxPackages_latest;
      # From steamac guest/kernel/patches: 16K-aligned blob placement, virtio-snd playback stalls.
      boot.kernelPatches =
        map
          (patch: {
            name = baseNameOf patch;
            inherit patch;
          })
          [
            ./patches/0001-drm-virtio-align-host-visible-blob-placement.patch
            ./patches/0006-ALSA-virtio-reset-partly-filled-periods-on-prepare.patch
            ./patches/0007-ALSA-virtio-report-an-xrun-when-a-whole-buffer-passed-unseen.patch
          ];
    };
}
