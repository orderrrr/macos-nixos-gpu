{ config, ... }:
{
  # Desktop shell on niri (bar, launcher on Mod+D, notifications, OSD), as vic/vix runs it.
  # Two layers: the files linked here are the read-only base; the settings UI saves over them to
  # ~/.local/state/noctalia, which is persisted.
  flake.modules.nixos.noctalia =
    { pkgs, ... }:
    let
      # Dimmed toward black so it sits behind the windows instead of competing with them.
      dimmedWallpaper = pkgs.runCommand "wallpaper.jpg" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
        magick ${./wallpaper.jpg} -fill black -colorize 35% $out
      '';
      # Noctalia reads every *.toml in its config directory; this one only needs a store path.
      wallpaper = pkgs.writeText "wallpaper.toml" ''
        [wallpaper.default]
        path = "${dimmedWallpaper}"
      '';
    in
    {
      programs.noctalia = {
        enable = true;
        systemd.enable = true; # started with niri's graphical-session.target
      };
      systemd.user.tmpfiles.rules = [
        "d %h/.config/noctalia"
        "L+ %h/.config/noctalia/config.toml - - - - ${./config.toml}"
        "L+ %h/.config/noctalia/wallpaper.toml - - - - ${wallpaper}"
        # Compline, the theme ghostty and nvim use.
        "L+ %h/.config/noctalia/palettes - - - - ${./palettes}"
      ];
      environment.persistence."/persist".users.${config.meta.username}.directories = [
        ".local/state/noctalia"
        # Its storage key lives in the Secret Service (GNOME Keyring, from niri's module). With
        # autologin nothing unlocks a login keyring, so the keyring has an empty password.
        ".local/share/keyrings"
      ];
    };
}
