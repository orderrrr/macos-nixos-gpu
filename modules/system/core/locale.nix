_: {
  flake.modules.nixos.locale = {
    time.timeZone = "Africa/Harare"; # the Mac's
    # The text console types like niri (features/niri/config.kdl) and the Mac: Colemak-DH ANSI.
    services.xserver.xkb = {
      layout = "us";
      variant = "colemak_dh";
    };
    console.useXkbConfig = true;
  };
}
