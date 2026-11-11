{ config, ... }:
{
  flake.modules.nixos.claude-code =
    { lib, pkgs, ... }:
    {
      # Unfree; allowed for this package alone.
      nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "claude-code";
      environment.systemPackages = [ pkgs.claude-code ];
      # Everything in one directory under ~/.config, including .claude.json (normally in ~): it is
      # rewritten by rename, which would replace a persisted file's symlink, but not a bind-mounted
      # directory.
      environment.variables.CLAUDE_CONFIG_DIR = "$HOME/.config/claude";
      environment.persistence."/persist".users.${config.meta.username}.directories = [ ".config/claude" ];
    };
}
