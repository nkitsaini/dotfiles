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
      name = "Breeze";
      package = pkgs.kdePackages.breeze-gtk;
    };
    iconTheme = {
      name = "Breeze";
      package = pkgs.kdePackages.breeze-icons;
    };
    cursorTheme = {
      name = "Breeze";
      package = pkgs.breeze-hacked-cursor-theme;
    };
  };

  home.pointerCursor = {
    gtk.enable = true;
    name = "Breeze";
    package = pkgs.breeze-hacked-cursor-theme;
    size = 16;
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
    platformTheme = "qtct";
    style.name = "fusion";
  };

  xdg.configFile = {
    "Kvantum/kvantum.kvconfig".source = (pkgs.formats.ini { }).generate "kvantum.kvconfig" {
      General.theme = "Breeze";
    };
    qt5ct = {
      target = "qt5ct/qt5ct.conf";
      text = pkgs.lib.generators.toINI { } {
        Appearance = {
          icon_theme = "breeze";
          style="Fusion";
        };
        Interface = {
          # Show only icons in toolbar, not the text
          toolbutton_style=0;
        };
      };
    };

    qt6ct = {
      target = "qt6ct/qt6ct.conf";
      text = pkgs.lib.generators.toINI { } {
        Appearance = {
          icon_theme = "breeze";
          style="Fusion";
        };
        Interface = {
          # Show only icons in toolbar, not the text
          toolbutton_style=0;
        };
      };
    };
  };
}
