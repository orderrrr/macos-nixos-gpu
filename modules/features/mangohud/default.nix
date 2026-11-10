_: {
  # Vulkan overlay for frame pacing: `mangohud ./app` (or MANGOHUD=1). In this VM only FPS and
  # frame times are meaningful; there are no GPU sensors to read.
  flake.modules.nixos.mangohud =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mangohud ];
      environment.sessionVariables.MANGOHUD_CONFIG = "fps,frametime,frame_timing";
    };
}
