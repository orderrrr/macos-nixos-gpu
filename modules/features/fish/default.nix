{ config, ... }:
{
  # config/ is a copy of nix-config's dotfiles/config/fish (os.fish = its os/linux.fish).
  flake.modules.nixos.fish =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      # History, universal variables and zoxide's jump list. fish saves fish_variables by renaming
      # a new file over it, which a file bind-mounted on its own refuses (EBUSY), so the whole
      # folder is kept; the linked config in it is linked again at every login.
      environment.persistence."/persist".users.${config.meta.username}.directories = [
        ".config/fish"
        ".local/share/fish"
        ".local/share/zoxide"
      ];
      users.defaultUserShell = pkgs.fish;
      # What config.fish calls: zoxide, fzf.fish (which uses fd and bat), lsd.
      environment.systemPackages = with pkgs; [
        zoxide
        fzf
        fishPlugins.fzf-fish
        fd
        bat
        lsd
      ];
      # File by file, since fish writes its own state (fish_variables) into ~/.config/fish.
      systemd.user.tmpfiles.rules = [
        "d %h/.config/fish"
        "L+ %h/.config/fish/config.fish - - - - ${./config/config.fish}"
        "L+ %h/.config/fish/os.fish - - - - ${./config/os.fish}"
        "L+ %h/.config/fish/functions - - - - ${./config/functions}"
      ];
    };
}
