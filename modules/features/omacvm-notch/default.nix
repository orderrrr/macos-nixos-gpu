_: {
  # Full screen including the notch (as omacvm's "fullpanel"): the launcher gives the VM the
  # MacBook's whole panel and tells it where the camera notch is (omacvm.fullpanel= on the kernel
  # command line, modules/hosts/vm/launcher), and the bar has to
  # fill the strip beside it. omacvm draws Omarchy's bar split around the notch; here Noctalia's
  # bar gets the strip's height and nothing in its centre. Other starts (a window, an external
  # display) get no notch, and the bar stays as features/noctalia has it.
  flake.modules.nixos.omacvm-notch =
    { lib, pkgs, ... }:
    let
      bar = pkgs.writeShellApplication {
        name = "omacvm-notch-bar";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnused
          pkgs.jq
          pkgs.niri
        ];
        text = ''
          out=$HOME/.config/noctalia/notch.toml
          # omacvm.fullpanel=LxRxHxWxD: the notch's left and right edges, the strip's height and
          # the panel's size, in the Mac's points.
          panel=$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^omacvm\.fullpanel=//p')
          if [ -z "$panel" ]; then
            rm -f "$out"
            exit 0
          fi
          IFS=x read -r _ _ strip width _ <<< "$panel"
          # Points to niri's logical pixels: the panel's pixels per point, over niri's scale.
          read -r pixels scale < <(niri msg --json outputs | jq -r 'first(.[]) | "\(.current_mode as $m | .modes[$m].width) \(.logical.scale)"')
          thickness=$(awk -v s="$strip" -v p="$pixels" -v w="$width" -v k="$scale" 'BEGIN { printf "%d", s * p / w / k + 0.5 }')
          # After config.toml, so these win. The clock leaves the centre, which is the notch, for
          # the front of features/noctalia's end list.
          cat > "$out" << EOF
          [bar.default]
          thickness = $thickness
          center = []
          end = ["clock", "tray", "mac", "battery", "notifications", "clipboard", "volume", "control-center", "session"]
          margin_ends = 0
          radius = 0
          EOF
        '';
      };
    in
    {
      systemd.user.services.omacvm-notch-bar = {
        description = "OmacVM.app: Noctalia's bar in the strip beside the notch";
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        # niri's socket (and its scale) are there once niri.service is up.
        after = [ "niri.service" ];
        before = [ "noctalia.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe bar;
        };
      };
    };
}
