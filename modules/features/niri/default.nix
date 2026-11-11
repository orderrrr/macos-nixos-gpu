{ config, ... }:
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

      # Portals stay niri's (gnome for screen sharing, gtk for the rest): xdg-desktop-portal-wlr
      # idled 6 MB heavier, as it loads Mesa up front, and can't share a single window.
      # File dialogs come from gtk, not Nautilus.
      programs.niri.useNautilus = false;
      # The document portal only hands files to Flatpak sandboxes, and there are none. Masked:
      # the xdg-desktop-portal package that ships it stays the stock, cached one.
      systemd.user.services.xdg-document-portal.enable = false;
      # niri starts xwayland-satellite when an X11 app connects; without it X11 apps don't open.
      environment.systemPackages = [ pkgs.xwayland-satellite ];
      # Where Mod+Shift+S saves (config.kdl's screenshot-path).
      environment.persistence."/persist".users.${config.meta.username}.directories = [ "pic" ];

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
