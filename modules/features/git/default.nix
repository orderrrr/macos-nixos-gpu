{ config, ... }:
{
  # The Mac's global git settings, with the personal address for this VM.
  flake.modules.nixos.git =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        lfs.enable = true;
        config = {
          user = {
            inherit (config.meta) name email;
          };
          core = {
            autocrlf = "input";
            pager = "delta";
          };
          interactive.diffFilter = "delta --color-only";
          delta.navigate = true;
          pull.rebase = true;
          merge.conflictStyle = "zdiff3";
        };
      };
      environment.systemPackages = [ pkgs.delta ];
    };
}
