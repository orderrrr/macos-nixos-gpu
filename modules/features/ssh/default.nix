{ config, ... }:
{
  # git over SSH from the VM with the Mac's key (copied into ~/.ssh by hand, never into the store).
  flake.modules.nixos.ssh = {
    environment.persistence."/persist".users.${config.meta.username}.directories = [
      {
        directory = ".ssh";
        mode = "0700";
      }
    ];
    # The key has a passphrase: asked once per login, then the agent (gcr's, already on) holds it.
    programs.ssh.extraConfig = ''
      AddKeysToAgent yes
    '';
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };
}
