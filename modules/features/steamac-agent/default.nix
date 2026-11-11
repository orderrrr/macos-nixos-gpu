{ inputs, ... }:
{
  # Same steamac commit build.sh builds the launcher from.
  flake-file.inputs.steamac = {
    url = "github:fxgl/steamac/407fb58b7459c65f49a7c65ddb875718a093f43b";
    flake = false;
  };

  # steamac's guest agent, talking to the launcher over its virtio-console ports:
  # - fx.clipboard: the clipboard shared with the Mac (launcher Settings > General). It owns and
  #   watches niri's Wayland clipboard (data-control); X11 apps reach it via xwayland-satellite.
  # - fx.clock: the Mac's time after it wakes and after a VM resume, so the wall clock is right
  #   at once instead of when timesyncd next polls (forward steps only).
  # - fx.sleep: suspending the guest asks the launcher to pause the whole VM (a click or key
  #   wakes it); a kernel suspend would hang, since nothing in a VM can wake it.
  flake.modules.nixos.steamac-agent =
    { lib, pkgs, ... }:
    let
      agent = pkgs.rustPlatform.buildRustPackage {
        pname = "fx-progress-agent";
        version = "1.0.0";
        src = "${inputs.steamac}/guest/progress-agent";
        cargoLock.lockFile = "${inputs.steamac}/guest/progress-agent/Cargo.lock";
      };

      # In place of systemd-sleep, as steamac's SteamOS does; the guest's clocks don't run while
      # the VM is paused, so the job must not time out.
      pauseInstead = {
        serviceConfig = {
          ExecStart = [
            ""
            "${agent}/bin/fx-progress-agent sleep suspend"
          ];
          TimeoutStartSec = "infinity";
        };
      };
    in
    {
      services.udev.extraRules = ''
        SUBSYSTEM=="virtio-ports", ATTR{name}=="fx.clipboard", MODE="0666"
        SUBSYSTEM=="virtio-ports", ATTR{name}=="fx.clock", TAG+="systemd", ENV{SYSTEMD_WANTS}+="fx-clock-sync.service"
      '';

      systemd.user.services.fx-clipboard = {
        description = "Clipboard shared with the Mac";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${agent}/bin/fx-progress-agent clipboard";
          Restart = "on-failure"; # it exits 0 by itself when the launcher has no clipboard port
          RestartSec = 2;
        };
      };

      systemd.services = {
        # Started by udev when the port appears; may set the clock and nothing else.
        fx-clock-sync = {
          description = "Wall clock from the Mac after sleep and resume";
          unitConfig.ConditionPathExists = "/dev/virtio-ports/fx.clock";
          serviceConfig = {
            ExecStart = "${agent}/bin/fx-progress-agent clock-sync";
            Restart = "on-failure";
            RestartSec = 2;
            CapabilityBoundingSet = [ "CAP_SYS_TIME" ];
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateNetwork = true;
          };
        };
      }
      // lib.genAttrs [
        "systemd-suspend"
        "systemd-hybrid-sleep"
        "systemd-suspend-then-hibernate"
      ] (_: pauseInstead);
    };
}
