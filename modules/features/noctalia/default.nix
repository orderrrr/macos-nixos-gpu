{ config, ... }:
{
  # Desktop shell on niri (bar, launcher on Mod+D, notifications, OSD), as vic/vix runs it. It
  # is set up through its own settings UI, so its config is persisted rather than in the repo;
  # it colours only itself (compline stays the source for niri and ghostty).
  flake.modules.nixos.noctalia = {
    programs.noctalia = {
      enable = true;
      systemd.enable = true; # started with niri's graphical-session.target
    };
    environment.persistence."/persist".users.${config.meta.username}.directories = [
      ".config/noctalia"
    ];
  };
}
