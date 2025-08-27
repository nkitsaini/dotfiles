# From: https://discourse.nixos.org/t/struggling-to-configure-gtk-qt-theme-on-laptop/42268
# - https://discourse.nixos.org/t/struggling-to-configure-gtk-qt-theme-on-laptop/42268/4
# - https://discourse.nixos.org/t/struggling-to-configure-gtk-qt-theme-on-laptop/42268/10
{ pkgs, ... }:
{
  # Installing breeze-qt6 installs kwallet, which in turn gets registered as dbus service, which in turn is detected by Brave browser and started on startup.
  # This makes kwallet ask for password. We mask the services to stop kwallet from starting.
  # We always want to use gnome-keyring.
  home.file.".local/share/dbus-1/services/org.kde.kwalletd6.service".text = ''
    [D-BUS Service]
    Name=org.kde.kwalletd6
    Exec=/bin/false
  '';

  home.file.".local/share/dbus-1/services/org.kde.kwalletd5.service".text = ''
    [D-BUS Service]
    Name=org.kde.kwalletd5
    Exec=/bin/false
  '';

  home.packages = with pkgs; [
    kdePackages.breeze-gtk
    kdePackages.breeze-icons
    kdePackages.breeze.qt5
    kdePackages.breeze

    # https://www.reddit.com/r/hyprland/comments/18ecoo3/comment/lcb7at8/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    kdePackages.qtsvg
  ];

  gtk = {
    enable = true;
    theme = {
      name = "Breeze";
      package = pkgs.kdePackages.breeze-gtk;
    };

    # iconTheme = {
    #   name = "Adwaita";
    #   package = pkgs.gnome.adwaita-icon-theme;
    # };
    iconTheme = {
      name = "breeze";
      package = pkgs.kdePackages.breeze-icons;
    };

    # See value of  `echo $XCURSOR_PATH` and `echo $XCURSOR_THEME` the path should contain a theme named directory containing icons
    # `echo ~/.nix-profile/share/icons/*/cursors`
    #
    cursorTheme = {
      name = "breeze_cursors";
      package = pkgs.kdePackages.breeze-icons;
      # size = 20;
    };
  };

  home.pointerCursor = {
    gtk.enable = true;
    name = "breeze_cursors";
    package = pkgs.kdePackages.breeze-icons;
    # size = 20;
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      gtk-theme = "Breeze";
      color-scheme = "prefer-light";
    };

    # For Gnome shell
    "org/gnome/shell/extensions/user-theme" = {
      name = "Breeze";
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "kde";
  };
}
