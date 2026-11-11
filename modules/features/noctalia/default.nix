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
        # Upstream 5.4.1 can destroy a wl_surface while zink still presents to it (the patch says
        # why); with it, Noctalia can draw on the GPU again.
        package = pkgs.noctalia.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./0001-finish-gl-work-before-the-wl_surface-is-destroyed.patch
          ];
        });
        systemd.enable = true; # started with niri's graphical-session.target
      };
      # Draw with software GL (llvmpipe), not zink: zink presents through Venus's Vulkan WSI,
      # which can still attach a frame after Noctalia destroys a surface (the launcher on close),
      # and niri then disconnects it ("invalid object"). Its surfaces are cheap to draw on the CPU.
      systemd.user.services.noctalia = {
        environment.LIBGL_ALWAYS_SOFTWARE = "1";
        serviceConfig.UnsetEnvironment = [ "MESA_LOADER_DRIVER_OVERRIDE" ];
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
