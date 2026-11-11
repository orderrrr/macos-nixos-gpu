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
    # Caches under ~/.local, so ~ holds only .config and .local besides your folders.
    environment.sessionVariables.XDG_CACHE_HOME = "$HOME/.local/cache";
    # Short names for the XDG folders apps use: downloads in ~/dwn, pictures in ~/pic.
    systemd.user.tmpfiles.rules = [
      "L+ %h/.config/user-dirs.dirs - - - - ${builtins.toFile "user-dirs.dirs" ''
        XDG_DOWNLOAD_DIR="$HOME/dwn"
        XDG_PICTURES_DIR="$HOME/pic"
      ''}"
    ];
  };
}
