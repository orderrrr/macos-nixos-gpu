_: {
  # GTK apps and ghostty's dark:/light: theme follow this through the desktop portal.
  flake.modules.nixos.darkMode = {
    programs.dconf.profiles.user.databases = [
      { settings."org/gnome/desktop/interface".color-scheme = "prefer-dark"; }
    ];
  };
}
