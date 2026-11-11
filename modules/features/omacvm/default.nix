{ inputs, config, ... }:
{
  # omacvm's guest side (https://github.com/gillesgoetsch/omacvm, MIT): its agents as they ship.
  # steamac's launcher speaks OmacVM.app's side of them (modules/hosts/vm/launcher).
  flake-file.inputs.omacvm = {
    url = "github:gillesgoetsch/omacvm/ebe2cbb15ddd7b2ee644b4ebcb9a0b2b87469e0f"; # v3.4.4
    flake = false;
  };

  # The agents talk to the launcher over its virtio-console ports, here org.omacvm.media: the VM's
  # player (MPRIS) as the Mac's Now Playing, so AirPods and Control Center play and pause it. The
  # clipboard is steamac's own (features/steamac-agent).
  flake.modules.nixos.omacvm =
    { lib, pkgs, ... }:
    let
      guest = "${inputs.omacvm}/src/app/guest";
      python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
      agent =
        name:
        pkgs.runCommand name { } ''
          install -Dm755 ${guest}/${name} $out/bin/${name}
          sed -i '1s|.*|#!${python}/bin/python3|' $out/bin/${name}
        '';
      media = agent "omacvm-media";
      # As omacvm's units: started with the desktop, only when the app gave the VM the port.
      portService = port: {
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig = {
          ConditionPathExists = "/dev/virtio-ports/${port}";
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
    in
    {
      # The desktop user opens the ports (omacvm's 70-omacvm-clipboard.rules). Not
      # services.udev.extraRules: those land in 99-local.rules, after udev has applied uaccess.
      services.udev.packages = [
        (pkgs.writeTextDir "lib/udev/rules.d/70-omacvm.rules" ''
          SUBSYSTEM=="virtio-ports", ATTR{name}=="org.omacvm.media", TAG+="uaccess"
          KERNEL=="video42", SUBSYSTEM=="video4linux", GROUP="video", MODE="0660", TAG+="uaccess"
          SUBSYSTEM=="virtio-ports", ATTR{name}=="org.omacvm.camera", GROUP="video", MODE="0660", TAG+="uaccess"
        '')
      ];

      # What omacvm's agents read about this VM (omacvm apply writes it there): a VM with the app's
      # ports, the Mac's 127.0.0.1 as gvproxy shows it to the VM, the VM's name for the Mac's
      # helpers (base64 of nixos-gpu-vm), its user.
      environment.etc."omacvm/env".text = ''
        OMACVM_VM_TYPE=app
        OMACVM_HOST=192.168.127.254
        OMACVM_VM_NAME_B64=bml4b3MtZ3B1LXZt
        OMACVM_USER=${config.meta.username}
        OMACVM_FEATURE_scroll_momentum=on
      '';
      environment.persistence."/persist" = {
        # Root's: scroll momentum's calibration, the Touch ID key.
        directories = [
          {
            directory = "/var/lib/omacvm";
            mode = "0700";
          }
        ];
        # The Bridge's token (copied in from the Mac once), which the Bridge client and the
        # gestures daemon prove to the Mac's helpers.
        users.${config.meta.username}.directories = [
          {
            directory = ".config/omacvm-bridge";
            mode = "0700";
          }
        ];
      };

      systemd.user.services.omacvm-media = lib.recursiveUpdate (portService "org.omacvm.media") {
        description = "AirPods and media controls (the VM's player as the Mac's Now Playing)";
        environment.GI_TYPELIB_PATH = "${pkgs.glib.out}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0";
        serviceConfig.ExecStart = "${media}/bin/omacvm-media";
      };
    };
}
