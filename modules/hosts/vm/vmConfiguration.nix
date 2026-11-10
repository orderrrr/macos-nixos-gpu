{ ... }:
{
  # What booting in steamac's libkrun launcher needs: no bootloader, root is the whole disk.
  flake.nixosModules.vmConfiguration =
    {
      config,
      pkgs,
      modulesPath,
      ...
    }:
    let
      toplevel = config.system.build.toplevel;
    in
    {
      imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

      nixpkgs.hostPlatform = "aarch64-linux";

      # libkrun boots the raw Image + initrd directly.
      boot.loader.grub.enable = false;
      boot.kernelParams = [ "console=hvc0" ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true; # the run app makes the disk bigger than the image
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

      # The launcher covers the screen with its boot overlay until the guest reports ready
      # (its SteamOS agent normally does), so report it once the console login has started.
      systemd.services.steamac-ready = {
        wantedBy = [ "multi-user.target" ];
        after = [ "getty@tty1.service" ];
        serviceConfig.Type = "oneshot";
        script = "echo ready > /dev/virtio-ports/fx.progress";
      };

      services.openssh.enable = true; # the launcher forwards 127.0.0.1:2222 to the guest's :22
    };
}
