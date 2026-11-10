{ ... }:
{
  # niri loads the cursor theme named "default" (it ignores XCURSOR_THEME), so make that one
  # inherit Bibata; without any, it falls back to a tiny built-in cursor.
  flake.modules.nixos.cursor =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.bibata-cursors
        (pkgs.writeTextDir "share/icons/default/index.theme" ''
          [Icon Theme]
          Inherits=Bibata-Modern-Ice
        '')
      ];
    };
}
