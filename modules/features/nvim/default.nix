_: {
  # config/ is a copy of nix-config's dotfiles/config/nvim.
  flake.modules.nixos.nvim =
    { pkgs, ... }:
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
      };
      # What the config needs at runtime: nvim-treesitter compiles parsers with the tree-sitter
      # CLI and a C compiler, telescope searches with rg and fd (vim.pack clones with git).
      environment.systemPackages = with pkgs; [
        tree-sitter
        gcc
        gnumake
        ripgrep
        fd
      ];
      # Entry by entry, since vim.pack writes its lockfile into ~/.config/nvim.
      systemd.user.tmpfiles.rules = [
        "d %h/.config/nvim"
        "L+ %h/.config/nvim/init.lua - - - - ${./config/init.lua}"
        "L+ %h/.config/nvim/lua - - - - ${./config/lua}"
        "L+ %h/.config/nvim/colors - - - - ${./config/colors}"
        "L+ %h/.config/nvim/local-plugins - - - - ${./config/local-plugins}"
      ];
    };
}
