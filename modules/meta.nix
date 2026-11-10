{ lib, ... }:
{
  # Who this machine is for, read by any module that needs it (user, git, nix).
  options.meta = lib.mkOption { type = lib.types.attrsOf lib.types.str; };

  config.meta = {
    username = "nmcintosh";
    name = "nmcintosh";
    email = "nathanielstewartmcintosh@gmail.com";
  };
}
