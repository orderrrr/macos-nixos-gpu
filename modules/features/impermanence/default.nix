{ inputs, config, ... }:
{
  # `/` is a tmpfs (hosts/vm), so the system starts empty every boot; what survives is listed
  # under environment.persistence, here for the system and in each feature for its own state.
  flake-file.inputs.impermanence = {
    url = "github:nix-community/impermanence";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.nixos.impermanence = {
    imports = [ inputs.impermanence.nixosModules.impermanence ];
    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        "/var/lib/nixos" # stable uids and gids
        "/var/lib/systemd" # timer stamps, so daily GC doesn't run at every boot
        "/var/log"
      ];
      files = [
        "/etc/machine-id"
        # The Mac knows this host by its keys (ssh nixos-gpu-vm).
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
        "/etc/ssh/ssh_host_mldsa44_ed25519_key"
        "/etc/ssh/ssh_host_mldsa44_ed25519_key.pub"
      ];
      users.${config.meta.username}.directories = [
        "opt"
        "Downloads"
        ".cache/nix"
        ".cache/zig"
      ];
    };
  };
}
