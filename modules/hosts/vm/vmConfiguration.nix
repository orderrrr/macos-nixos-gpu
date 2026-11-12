_: {
  # What booting in steamac's libkrun launcher needs: no bootloader, root is the whole disk.
  flake.modules.nixos.vmConfiguration =
    {
      config,
      lib,
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
      boot.kernelParams = [
        "console=hvc0"
        # glibc 2.44 madvises malloc heaps for 2 MB huge pages, which held 352 of 546 MB of
        # anon memory on the desktop (each fish shell ~10 MB) for no felt speedup.
        "transparent_hugepage=never"
        # Idle wakeups, each a VM exit the Mac pays for: virtio-gpu's vblank is a timer at the
        # display's rate that DRM keeps running 5 s after every frame (100 ms here, as omacvm),
        # and RCU's callbacks are batched (the kernel's RCU_LAZY, which needs them offloaded).
        "drm.vblankoffdelay=100"
        "rcu_nocbs=all"
      ];

      # Impermanence (features/impermanence): `/` starts empty every boot. The disk holds the
      # store (and the system profiles the kernel boots) and /persist.
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
        options = [ "mode=755" ];
      };
      fileSystems."/disk" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true; # the run app makes the disk bigger than the image
        neededForBoot = true;
      };
      fileSystems."/nix" = {
        device = "/disk/nix";
        fsType = "none";
        options = [ "bind" ];
        neededForBoot = true;
      };
      fileSystems."/persist" = {
        device = "/disk/persist";
        fsType = "none";
        options = [ "bind" ];
        neededForBoot = true;
      };
      # Builds in the default /tmp would fill RAM.
      nix.settings.build-dir = "/nix/var/nix/builds";
      systemd.tmpfiles.rules = [ "d /nix/var/nix/builds 0755 root root" ];

      # First boot: register the image's store paths, as the sd-image module does.
      boot.postBootCommands = ''
        if [ -f /disk/nix-path-registration ]; then
          ${config.nix.package.out}/bin/nix-store --load-db < /disk/nix-path-registration
          rm -f /disk/nix-path-registration
        fi
        touch /etc/NIXOS # the tmpfs root starts without it
      '';

      # The image starts with this build as system generation 1, and the kernel boots whatever
      # the system profile points at, so nixos-rebuild in the guest takes effect on reboot.
      system.build.rootfs = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
        storePaths = [ toplevel ];
        volumeLabel = "nixos";
        populateImageCommands = ''
          mkdir -p ./files/persist ./files/nix/var/nix/profiles ./files/nix/var/nix/builds
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

      # The launcher covers the screen with its boot screen until the guest reports ready (its
      # SteamOS agent normally does): reported once niri and its bar are up, so the boot screen
      # fades straight into the desktop.
      systemd.user.services.boot-ready = {
        # Not graphical-session.target: a target orders itself after what it wants, and noctalia
        # comes after the target, a cycle in which systemd drops this unit.
        wantedBy = [ "noctalia.service" ];
        after = [
          "niri.service"
          "noctalia.service"
        ];
        unitConfig.ConditionPathExists = "/dev/virtio-ports/fx.progress";
        serviceConfig.Type = "oneshot";
        script = "echo ready > /dev/virtio-ports/fx.progress";
      };
      services.udev.extraRules = ''
        SUBSYSTEM=="virtio-ports", ATTR{name}=="fx.progress", MODE="0666"
      '';

      services.openssh.enable = true; # the launcher forwards 127.0.0.1:2222 to the guest's :22

      # Memory: no name-service cache daemon (its only plugins look up containers and the own
      # hostname, which /etc/hosts has), and no login on hvc0, which the launcher only reads as a log.
      services.nscd.enable = false;
      # A 10-way C++ build once ran the VM out of memory and the kernel killed niri: compressed swap
      # in RAM gives headroom before anything is killed, and in-VM builds use at most 4 cores.
      zramSwap.enable = true;
      # Past what zram can hold: a swap file on the disk (/ is tmpfs), used only once zram is
      # full (zram's priority is 5).
      swapDevices = [
        {
          device = "/disk/swapfile";
          size = 8 * 1024;
          priority = 0;
        }
      ];
      nix.settings = {
        cores = 4;
        max-jobs = 1;
      };
      system.nssModules = lib.mkForce [ ];
      systemd.services."serial-getty@hvc0".enable = false;
      # The journal is on /persist and journald maps its files, which had grown to 80 MB.
      services.journald.settings.Journal.SystemMaxUse = "50M";
      # Free guest pages go back to macOS through the balloon's free page reporting, which by
      # default only reports 2 MB blocks; freed memory is mostly scattered, so 16 KB (a Mac page)
      # returned 450 MB more. File cache isn't free, and macOS already caches the same disk
      # image, so clean cache is dropped every 5 minutes for the balloon to report.
      systemd.tmpfiles.settings.page-reporting."/sys/module/page_reporting/parameters/page_reporting_order".w.argument =
        "2";
      systemd.services.drop-page-cache = {
        startAt = "*:0/5";
        serviceConfig.Type = "oneshot";
        script = "echo 1 > /proc/sys/vm/drop_caches";
      };
    };
}
