{ config, ... }:
{
  # Desktop shell on niri (bar, launcher on Mod+D, notifications, OSD), as vic/vix runs it.
  # Two layers: the files linked here are the read-only base; the settings UI saves over them to
  # ~/.local/state/noctalia, which is persisted.
  flake.modules.nixos.noctalia =
    { pkgs, ... }:
    let
      # The bright bands recoloured orange (a luminance mask keeps the navy, the blues and the
      # halftone texture), then dimmed toward black so it sits behind the windows.
      dimmedWallpaper = pkgs.runCommand "wallpaper.jpg" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
        magick ${./wallpaper.jpg} \
          \( +clone -colorspace gray +level-colors black,'#e8743c' \) \
          \( -clone 0 -colorspace gray -level 40%,95% \) \
          -composite -fill black -colorize 35% $out
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
        # Upstream 5.4.1 can destroy a wl_surface while zink still presents to it, and niri then
        # disconnects Noctalia (the bar vanished on every few Mod+D). The patch waits for that
        # present first (it says how), so Noctalia draws on the GPU.
        package = pkgs.noctalia.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./0001-finish-gl-work-before-the-wl_surface-is-destroyed.patch
          ];
        });
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
