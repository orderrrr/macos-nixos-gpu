{ ... }:
{
  # The Mac's global git settings, with the personal address for this VM.
  flake.nixosModules.git =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        lfs.enable = true;
        config = {
          user = {
            name = "nmcintosh";
            email = "nathanielstewartmcintosh@gmail.com";
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
