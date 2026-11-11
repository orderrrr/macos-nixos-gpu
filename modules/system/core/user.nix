{ config, ... }:
let
  inherit (config.meta) username;
in
{
  flake.modules.nixos.user = {
    imports = [ config.flake.modules.nixos.fish ];
    # Users only as declared here, applied at every boot (the root fs is a tmpfs anyway).
    users.mutableUsers = false;
    users.users.${username} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "video"
        "audio"
      ];
      openssh.authorizedKeys.keyFiles = [ ./id_ed25519.pub ];
      # The sudo password's hash, kept out of the (public) repo, made once with
      # `mkpasswd | sudo tee /persist/passwords/<user>`.
      hashedPasswordFile = "/persist/passwords/${username}";
    };
    # sudo asks for that password: root controls the guest kernel, and with it the requests sent
    # to the Mac over virtio-fs (hosts/vm/libkrun keeps those inside the share; this is the
    # layer before it), so nothing running as the user should get root for free.
    security.sudo.wheelNeedsPassword = true;
    # The Mac stays able to administer the guest without that password (key only; root has no
    # password): to make the password file on a new disk, and for rebuilds over SSH.
    users.users.root.openssh.authorizedKeys.keyFiles = [ ./id_ed25519.pub ];
    services.getty.autologinUser = username;
  };
}
