{ ... }:
{
  flake.modules.nixos.niri =
    { pkgs, ... }:
    let
      # Only the one file, not niri's whole source tree, goes into the system.
      defaultConfig = pkgs.runCommand "niri-default-config.kdl" { } ''
        cp ${pkgs.niri.src}/resources/default-config.kdl $out
      '';
    in
    {
      programs.niri.enable = true;
      environment.systemPackages = [ pkgs.fuzzel ]; # niri's default Mod+D

      # niri reads this when there is no ~/.config/niri/config.kdl.
      environment.etc."niri/config.kdl".text = ''
        include "${defaultConfig}"
        include "${./config.kdl}"
      '';

      # Console login on tty1 starts niri. niri-session re-runs itself through a login shell,
      # so the guard keeps that shell from starting it again.
      environment.loginShellInit = ''
        if [ "$(tty)" = /dev/tty1 ] && [ -z "$NIRI_FROM_LOGIN" ]; then
          export NIRI_FROM_LOGIN=1
          exec niri-session
        fi
      '';
    };
}
