{ inputs, ... }:
{
  # Same steamac commit build.sh builds the launcher from.
  flake-file.inputs.steamac = {
    url = "github:fxgl/steamac/407fb58b7459c65f49a7c65ddb875718a093f43b";
    flake = false;
  };

  # The clipboard shared with the Mac: steamac's guest agent owns and watches the clipboard on
  # niri's Wayland display (data-control) and xwayland-satellite's X display, and talks to the
  # launcher over the virtio port fx.clipboard (launcher Settings > General, on by default).
  flake.modules.nixos.mac-clipboard =
    { pkgs, ... }:
    let
      agent = pkgs.rustPlatform.buildRustPackage {
        pname = "fx-progress-agent";
        version = "1.0.0";
        src = "${inputs.steamac}/guest/progress-agent";
        cargoLock.lockFile = "${inputs.steamac}/guest/progress-agent/Cargo.lock";
      };
    in
    {
      services.udev.extraRules = ''
        SUBSYSTEM=="virtio-ports", ATTR{name}=="fx.clipboard", MODE="0666"
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
    };
}
