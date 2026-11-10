{ ... }:
{
  flake.modules.nixos.ghostty =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ghostty ];
      fonts.packages = [ pkgs.ibm-plex ];

      # ghostty only reads ~/.config/ghostty, and its D-Bus and systemd launchers call the
      # unwrapped binary, so link the config there rather than wrapping the package.
      systemd.user.tmpfiles.rules = [ "L+ %h/.config/ghostty - - - - ${./config}" ];
    };
}
