_: {
  flake.modules.nixos.audio = {
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      # Its X11 bell module connects to $DISPLAY at startup, which alone makes niri start
      # Xwayland; nothing here rings the X bell.
      extraConfig.pipewire."99-no-x11-bell"."context.properties"."module.x11.bell" = false;
    };
  };
}
