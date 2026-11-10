{ ... }:
{
  # GTK apps and ghostty's dark:/light: theme follow this through the desktop portal.
  flake.nixosModules.darkMode = {
    programs.dconf.profiles.user.databases = [
      { settings."org/gnome/desktop/interface".color-scheme = "prefer-dark"; }
    ];
  };
}
