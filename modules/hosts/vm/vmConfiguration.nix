_: {
  # What booting in steamac's libkrun launcher needs: no bootloader, root is the whole disk.
  flake.modules.nixos.vmConfiguration =
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
      nixpkgs.hostPlatform = "aarch64-linux";

      # libkrun boots the raw Image + initrd directly.
      boot.loader.grub.enable = false;
      boot.kernelParams = [ "console=hvc0" ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true; # the run app makes the disk bigger than the image
      };

      # The repo on the Mac (the run app's --share), for nixos-rebuild in the guest.
      fileSystems."/etc/nixos" = {
        device = "macshare";
        fsType = "virtiofs";
      };

      # First boot: register the image's store paths, as the sd-image module does.
      boot.postBootCommands = ''
        if [ -f /nix-path-registration ]; then
          ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
          touch /etc/NIXOS
          rm -f /nix-path-registration
        fi
      '';

      # The image starts with this build as system generation 1, and the kernel boots whatever
      # the system profile points at, so nixos-rebuild in the guest takes effect on reboot.
      system.build.rootfs = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
        storePaths = [ toplevel ];
        volumeLabel = "nixos";
        populateImageCommands = ''
          mkdir -p ./files/nix/var/nix/profiles
          ln -s ${toplevel} ./files/nix/var/nix/profiles/system-1-link
          ln -s system-1-link ./files/nix/var/nix/profiles/system
        '';
      };
      system.build.bundle = pkgs.runCommand "nixos-gpu-vm" { } ''
        mkdir $out
        ln -s ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} $out/Image
        ln -s ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} $out/initrd
        echo "init=/nix/var/nix/profiles/system/init ${toString config.boot.kernelParams}" > $out/cmdline
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
