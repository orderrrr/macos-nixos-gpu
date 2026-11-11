_: {
  # The Mac folder ~/VM (the run app's single --share) at /mnt/mac. Its hidden .nixos-gpu-vm is
  # this repo, bound to /etc/nixos for nixos-rebuild; whatever else you put there is linked into ~
  # by name, so files move between Finder and the VM's home. Names already in ~ are left alone,
  # and hidden items (the repo, .DS_Store and the like) aren't linked.
  flake.modules.nixos.mac-share =
    { pkgs, ... }:
    {
      fileSystems."/mnt/mac" = {
        device = "macshare";
        fsType = "virtiofs";
      };
      fileSystems."/etc/nixos" = {
        device = "/mnt/mac/.nixos-gpu-vm";
        fsType = "none";
        options = [ "bind" ];
      };

      # virtio-fs doesn't report changes made on the Mac, so the links are checked every 2 s.
      systemd.user.services.mac-share-links = {
        description = "Link ~/VM's items from the Mac into ~";
        wantedBy = [ "default.target" ];
        path = [ pkgs.coreutils ];
        script = ''
          while true; do
            for item in /mnt/mac/*; do
              [ -e "$item" ] || continue
              name=''${item##*/}
              [ -e "$HOME/$name" ] || [ -L "$HOME/$name" ] || ln -s "$item" "$HOME/$name"
            done
            for link in "$HOME"/*; do
              [ -L "$link" ] || continue
              case "$(readlink "$link")" in
                /mnt/mac/*) [ -e "$link" ] || rm -f "$link" ;;
              esac
            done
            sleep 2
          done
        '';
      };
    };
}
