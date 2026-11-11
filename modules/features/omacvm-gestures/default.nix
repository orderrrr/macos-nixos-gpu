{ inputs, ... }:
{
  # The Mac's trackpad gestures in niri (OmacVM.app's "Trackpad gestures" and "macOS-native scroll
  # momentum"). While the VM is in front and full screen, OmacVMGestures.app on the Mac reads the
  # trackpad's fingers and sends 3+-finger frames, pinches and, with scroll momentum, two-finger
  # scrolling to omacvm's daemon here, which replays them on a virtual Apple touchpad for libinput
  # and niri. The Mac's helper lets the daemon in only once it proves it knows the Bridge's token.
  #
  # Once per Mac:
  # 1. The helper runs from a copy of its own: build.sh signs OmacVM.app again on every run, and
  #    macOS ties the helper's permissions to its signature.
  #      ditto ~/.local/share/nixos-gpu-vm/OmacVM.app/Contents/Helpers/OmacVMGestures.app \
  #        ~/Applications/OmacVMGestures.app
  #      open ~/Applications/OmacVMGestures.app
  #    and allow it Accessibility and Input Monitoring in System Settings › Privacy & Security.
  #    Its log is ~/Library/Logs/omacvm-gestures.log.
  # 2. The token: the helper reads ~/Library/Application Support/omacvm-bridge/token, which only
  #    omacvm's installer or OmacVMBridge.app makes. The daemon reads it from the desktop user's
  #    ~/.config/omacvm-bridge/token (their own plain file, kept across boots below). Made on the
  #    Mac and copied over SSH, as `omacvm apply` does, it never touches the Mac folder's 9p share:
  #      sh -c 't="$HOME/Library/Application Support/omacvm-bridge/token"
  #        [ -s "$t" ] || { mkdir -p -m 700 "${t%/*}" && (umask 077; openssl rand -hex 32 > "$t"); }
  #        ssh nixos-gpu-vm "umask 077; mkdir -p .config/omacvm-bridge; cat > .config/omacvm-bridge/token" < "$t"'
  flake.modules.nixos.omacvm-gestures =
    { lib, pkgs, ... }:
    let
      python = pkgs.python3.withPackages (p: [ p.evdev ]);
      daemon = pkgs.runCommand "omacvm-gestures" { } ''
        install -Dm755 ${inputs.omacvm}/src/gestures/guest/omacvm-gestures $out/bin/omacvm-gestures
        sed -i '1s|.*|#!${python}/bin/python3|' $out/bin/omacvm-gestures
      '';
    in
    {
      # /etc/omacvm/env (the omacvm module) names the VM for the helper, which sends to the VM
      # named in the front window's title, and turns scroll momentum on.

      # As omacvm's unit: root, for /dev/uinput.
      systemd.services.omacvm-gestures = {
        description = "omacvm-gestures: Mac trackpad gestures on a virtual touchpad";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        # runuser and notify-send, for its one notice (the escape combo of older helpers).
        path = [
          pkgs.util-linux
          pkgs.libnotify
        ];
        serviceConfig = {
          EnvironmentFile = "/etc/omacvm/env";
          ExecStart = "${daemon}/bin/omacvm-gestures";
          Restart = "always";
          RestartSec = 2;
        };
      };

      environment.etc."niri/config.kdl".text = lib.mkAfter ''
        include "${./niri.kdl}"
      '';
    };
}
