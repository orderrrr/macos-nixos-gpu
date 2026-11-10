_: {
  # config/ is a copy of nix-config's dotfiles/config/fish (os.fish = its os/linux.fish).
  flake.modules.nixos.fish =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
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
