{ ... }:
{
  # The Mac side of the VM, for a nix-darwin config to import (nix-config does, as
  # inputs.nixos-gpu-vm.modules.darwin.vmHost): the aarch64-linux builder the guest's kernel,
  # Mesa and rootfs build on. Changing the size needs a running builder, since the builder VM
  # itself is built on aarch64-linux.
  flake.modules.darwin.vmHost = {
    nix.linux-builder = {
      enable = true;
      maxJobs = 8;
      config.virtualisation = {
        cores = 8; # QEMU's mach-virt here allows at most 8 vCPUs
        # The disk image on the Mac only grows, so diskSize caps it; results are copied back
        # to the Mac, so the builder collects garbage early (under 5 GiB free, up to 15).
        darwin-builder = {
          memorySize = 16 * 1024;
          diskSize = 40 * 1024;
          min-free = 5 * 1024 * 1024 * 1024;
          max-free = 15 * 1024 * 1024 * 1024;
        };
      };
    };
  };
}
