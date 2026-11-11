{ config, ... }:
{
  # GPU: Vulkan only through our Venus ICD; GL (niri, ghostty, zen) through zink on top of
  # it, since the host offers no virgl GL.
  flake.modules.nixos.venus =
    { pkgs, ... }:
    let
      mesa = pkgs.callPackage ./_mesa.nix { };
    in
    {
      hardware.graphics.enable = true;
      # Compiled shaders, so Vulkan and zink apps start fast after a reboot.
      environment.persistence."/persist".users.${config.meta.username}.directories = [
        ".local/cache/mesa_shader_cache"
      ];
      environment.sessionVariables = {
        VK_DRIVER_FILES = "${mesa}/share/vulkan/icd.d/virtio_icd.aarch64.json";
        MESA_LOADER_DRIVER_OVERRIDE = "zink";
      };
      environment.systemPackages = [ pkgs.vulkan-tools ];
    };
}
