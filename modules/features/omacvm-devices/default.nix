{ inputs, ... }:
let
  # Both agents do nothing unless this file names an OmacVM.app VM (omacvm's apply writes it).
  # A path, not text: the two modules define it alike and an equal path merges, where text would
  # be written twice.
  agent =
    pkgs: source:
    pkgs.runCommand (baseNameOf source) { } ''
      install -Dm755 ${source} $out/bin/${baseNameOf source}
      sed -i '1s|.*|#!${pkgs.python3}/bin/python3|' $out/bin/${baseNameOf source}
    '';
in
{
  # The Mac's battery as BAT0 and ADP0 (UPower, so Noctalia's battery widget). OmacVM.app sends
  # the Mac's snapshots on org.omacvm.battery; omacvm-battery writes each one to the module.
  flake.modules.nixos.omacvm-battery =
    { config, pkgs, ... }:
    let
      guest = "${inputs.omacvm}/src/battery/guest";
      module = config.boot.kernelPackages.callPackage ./_battery-module.nix { src = "${guest}/module"; };
      battery = agent pkgs "${guest}/omacvm-battery";
    in
    {
      boot.extraModulePackages = [ module ];
      boot.kernelModules = [ "omacvm_battery" ];
      # Root only: the agent is the port's one reader (70-omacvm-battery.rules).
      services.udev.extraRules = ''
        SUBSYSTEM=="virtio-ports", ATTR{name}=="org.omacvm.battery", MODE="0600"
      '';

      # The battery is the Mac's: the VM never suspends or powers off for it, the Mac decides.
      services.upower = {
        enable = true;
        allowRiskyCriticalPowerAction = true;
        criticalPowerAction = "Ignore";
      };

      systemd.services.omacvm-battery = {
        description = "OmacVM.app: the Mac's battery (BAT0, ADP0)";
        wantedBy = [ "multi-user.target" ];
        # The agent waits for udev to name the port, and exits when the Mac's side goes away.
        unitConfig = {
          ConditionPathExists = "/sys/devices/platform/omacvm-battery/state";
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          ExecStart = "${battery}/bin/omacvm-battery";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
    };

  # The Mac's camera as /dev/video42, "Mac Camera". omacvm-camera, as the desktop user, asks
  # OmacVM.app for frames on org.omacvm.camera only while an app reads the camera, so the Mac's
  # camera and its green light are off otherwise.
  flake.modules.nixos.omacvm-camera =
    { config, pkgs, ... }:
    let
      camera = agent pkgs "${inputs.omacvm}/src/camera/guest/omacvm-camera";
    in
    {
      # omacvm-camera needs v4l2loopback's client-usage events (0.13 or newer).
      boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
      boot.kernelModules = [ "v4l2loopback" ];
      # exclusive_caps: apps see a normal camera once omacvm-camera has written its first frame.
      boot.extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=42 card_label="Mac Camera" exclusive_caps=1 max_openers=10
      '';
      # The camera and its port for the logged-in user: the omacvm module's 70-omacvm.rules.

      systemd.user.services.omacvm-camera = {
        description = "OmacVM.app: the Mac's camera as /dev/video42 (Mac Camera)";
        wantedBy = [ "default.target" ];
        # Not for root's own manager (an SSH login): it would take /dev/video42 before the
        # desktop user's.
        unitConfig = {
          ConditionUser = "!@system";
          ConditionPathExists = "/dev/virtio-ports/org.omacvm.camera";
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          ExecStart = "${camera}/bin/omacvm-camera";
          Restart = "always";
          RestartSec = 2;
        };
      };
    };
}
