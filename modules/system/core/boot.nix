{ ... }:
{
  flake.modules.nixos.bootloader =
    { pkgs, ... }:
    let
      # kernel.config is steamac's guest/kernel/config fragments (libkrunfw base, Steam Frame
      # userspace, steamac) resolved for this kernel with olddefconfig and every module built
      # in, as steamac's build does. NixOS's generic config builds thousands of modules this VM
      # never loads (over an hour and 40 GB on the builder). Regenerate it on a kernel bump.
      kernel = (pkgs.linuxManualConfig {
        inherit (pkgs.linux_latest) src version;
        configfile = ./kernel.config;
        # From steamac guest/kernel/patches: 16K-aligned blob placement, virtio-snd playback stalls.
        kernelPatches =
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
      }).overrideAttrs (old: {
        # nixpkgs deletes each module's certificate with `xargs rm`, which fails when there are
        # no modules at all (rm without operands).
        postInstall = builtins.replaceStrings [ "xargs -d'\\n' rm" ] [ "xargs -r -d'\\n' rm" ] old.postInstall;
      });
    in
    {
      boot.kernelPackages = pkgs.linuxPackagesFor kernel;
      # Everything is built in, so there is nothing for the initrd to load. systemd still asks
      # for modules this VM has no hardware for (efivarfs, tpm-crb, tpm-tis); skip those.
      boot.initrd.includeDefaultModules = false;
      boot.initrd.allowMissingModules = true;
    };
}
