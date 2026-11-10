{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  venus = pkgs.callPackage ./venus.nix { };
  toplevel = config.system.build.toplevel;
in
{
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

  # libkrun boots the raw Image + initrd directly: no bootloader, root is the whole /dev/vda.
  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # From steamac guest/kernel/patches: 16K-aligned blob placement, virtio-snd playback stalls.
  boot.kernelPatches =
    map
      (patch: {
        name = baseNameOf patch;
        inherit patch;
      })
      [
        ./patches/kernel/0001-drm-virtio-align-host-visible-blob-placement.patch
        ./patches/kernel/0006-ALSA-virtio-reset-partly-filled-periods-on-prepare.patch
        ./patches/kernel/0007-ALSA-virtio-report-an-xrun-when-a-whole-buffer-passed-unseen.patch
      ];
  boot.kernelParams = [ "console=hvc0" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true; # run.sh makes the disk bigger than the image
  };

  # First boot: register the image's store paths, as the sd-image module does.
  boot.postBootCommands = ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
      touch /etc/NIXOS
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      rm -f /nix-path-registration
    fi
  '';

  system.build.rootfs = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
    storePaths = [ toplevel ];
    volumeLabel = "nixos";
  };
  system.build.bundle = pkgs.runCommand "nixos-gpu-vm" { } ''
    mkdir $out
    ln -s ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} $out/Image
    ln -s ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} $out/initrd
    echo "init=${toplevel}/init ${toString config.boot.kernelParams}" > $out/cmdline
  '';

  # GPU: Vulkan only through our Venus ICD; GL (niri, alacritty) through zink on top of it,
  # since the host offers no virgl GL.
  hardware.graphics.enable = true;
  environment.sessionVariables = {
    VK_DRIVER_FILES = "${venus}/share/vulkan/icd.d/virtio_icd.aarch64.json";
    MESA_LOADER_DRIVER_OVERRIDE = "zink";
  };

  programs.niri.enable = true;
  environment.systemPackages = [
    pkgs.alacritty # niri's default Mod+T
    pkgs.fuzzel # niri's default Mod+D
    pkgs.vulkan-tools
  ];

  users.users.nmcintosh = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
    openssh.authorizedKeys.keyFiles = [ ./id_ed25519.pub ];
  };
  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = "nmcintosh";
  # Console login on tty1 starts niri. niri-session re-runs itself through a login shell,
  # so the guard keeps that shell from starting it again.
  environment.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "$NIRI_FROM_LOGIN" ]; then
      export NIRI_FROM_LOGIN=1
      exec niri-session
    fi
  '';

  services.openssh.enable = true; # launcher forwards 127.0.0.1:<ssh-port> to the guest's :22
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  system.stateVersion = "26.11";
}
