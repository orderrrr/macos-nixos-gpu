{ config, ... }:
{
  # Desktop shell on niri (bar, launcher on Mod+D, notifications, OSD), as vic/vix runs it.
  # Two layers: config.toml here is the read-only base; the settings UI saves over it to
  # ~/.local/state/noctalia, which is persisted. It colours only itself (compline stays the
  # source for niri and ghostty).
  flake.modules.nixos.noctalia = {
    programs.noctalia = {
      enable = true;
      systemd.enable = true; # started with niri's graphical-session.target
    };
    systemd.user.tmpfiles.rules = [
      "d %h/.config/noctalia"
      "L+ %h/.config/noctalia/config.toml - - - - ${./config.toml}"
    ];
    environment.persistence."/persist".users.${config.meta.username}.directories = [
      ".local/state/noctalia"
      # Its storage key lives in the Secret Service (GNOME Keyring, from niri's module). With
      # autologin nothing unlocks a login keyring, so the keyring has an empty password.
      ".local/share/keyrings"
    ];
  };
}
