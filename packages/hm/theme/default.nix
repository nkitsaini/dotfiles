# From: https://discourse.nixos.org/t/struggling-to-configure-gtk-qt-theme-on-laptop/42268
# - https://discourse.nixos.org/t/struggling-to-configure-gtk-qt-theme-on-laptop/42268/4
# - https://discourse.nixos.org/t/struggling-to-configure-gtk-qt-theme-on-laptop/42268/10
{ pkgs, ... }:
{
  # gtk = {
  #   enable = true;
  #   cursorTheme.name = "Adwaita";
  #   cursorTheme.package = pkgs.adwaita-icon-theme;
  #   theme.name = "adw-gtk3-light";
  #   theme.package = pkgs.adw-gtk3;
  #   iconTheme = {
  #     package = pkgs.adwaita-icon-theme;
  #     name = "adwaita-icon-theme";
  #   };
  # };

  # qt.enable = true;
  # qt.platformTheme.name = "qtct";
  # xdg.configFile."qt5ct/qt5ct.conf".text = ''
  #   [Appearance]
  #   icon_theme=breeze
  # '';

  home.packages = with pkgs; [

    papirus-folders
    
  ];

  gtk = {
    enable = true;
    theme = {
      name = "Catppuccin-Macchiato-Standard-Blue-Light";
      package = pkgs.catppuccin-gtk.override {
        accents = [ "blue" ];
        size = "standard";
        variant = "macchiato";
      };
    };
    iconTheme = {
      name = "Papirus-Light";
      package = pkgs.catppuccin-papirus-folders.override {
        flavor = "macchiato";
        accent = "blue";
      };
    };
    cursorTheme = {
      name = "Catppuccin-Macchiato-Light-Cursors";
      package = pkgs.catppuccin-cursors.macchiatoLight;
    };
    gtk3 = {
      extraConfig.gtk-application-prefer-dark-theme = false;
    };
  };

  home.pointerCursor = {
    gtk.enable = true;
    name = "Catppuccin-Macchiato-Light-Cursors";
    package = pkgs.catppuccin-cursors.macchiatoLight;
    size = 16;
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      gtk-theme = "Catppuccin-Macchiato-Standard-Blue-Light";
      color-scheme = "prefer-light";
    };

    # For Gnome shell
    "org/gnome/shell/extensions/user-theme" = {
      name = "Catppuccin-Macchiato-Standard-Blue-Light";
    };
  };

  qt = {
    enable = true;
    platformTheme = "qtct";
    style.name = "kvantum";
  };

  xdg.configFile = {
    "Kvantum/kvantum.kvconfig".source = (pkgs.formats.ini { }).generate "kvantum.kvconfig" {
      General.theme = "Catppuccin-Macchiato-Blue";
    };
    qt5ct = {
      target = "qt5ct/qt5ct.conf";
      text = pkgs.lib.generators.toINI { } {
        Appearance = {
          icon_theme = "Papirus-Light";
        };
      };
    };

    qt6ct = {
      target = "qt6ct/qt6ct.conf";
      text = pkgs.lib.generators.toINI { } {
        Appearance = {
          icon_theme = "Papirus-Light";
        };
      };
    };
  };
}
