_: {
  # GPU: Vulkan only through our Venus ICD; GL (niri, ghostty, zen) through zink on top of
  # it, since the host offers no virgl GL.
  flake.modules.nixos.venus =
    { pkgs, ... }:
    let
      mesa = pkgs.callPackage ./_mesa.nix { };
    in
    {
      hardware.graphics.enable = true;
      environment.sessionVariables = {
        VK_DRIVER_FILES = "${mesa}/share/vulkan/icd.d/virtio_icd.aarch64.json";
        MESA_LOADER_DRIVER_OVERRIDE = "zink";
      };
      environment.systemPackages = [ pkgs.vulkan-tools ];
    };
}
