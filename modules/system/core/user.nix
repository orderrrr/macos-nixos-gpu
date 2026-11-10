{ config, ... }:
let
  inherit (config.meta) username;
in
{
  flake.modules.nixos.user = {
    imports = [ config.flake.modules.nixos.fish ];
    users.users.${username} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "video"
        "audio"
      ];
      openssh.authorizedKeys.keyFiles = [ ./id_ed25519.pub ];
    };
    security.sudo.wheelNeedsPassword = false;
    services.getty.autologinUser = username;
  };
}
