_: {
  # Per-project dev shells: a project's `.envrc` (`use flake`) loads its flake's devShell on cd.
  flake.modules.nixos.direnv = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    # Daily GC would otherwise drop the build inputs of dev shells between uses.
    nix.settings.keep-outputs = true;
    programs.git.config.core.excludesFile = "${builtins.toFile "gitignore" ''
      .envrc
      .direnv
    ''}";
  };
}
