{ ... }:
{
  flake.nixosModules.user = {
    users.users.nmcintosh = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "video"
        "audio"
      ];
      openssh.authorizedKeys.keyFiles = [ ./id_ed25519.pub ];
    };
    security.sudo.wheelNeedsPassword = false;
    services.getty.autologinUser = "nmcintosh";
  };
}
