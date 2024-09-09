# Has everything except for desktop manager.
# It is good to be used in nixos or standalone home-manager for desktop setups.
{ pkgs, nixGLCommandPrefix ? "", ... }: {
  imports = [ ./setup-minimal.nix ./wezterm ./firefox.nix ./mpv ];

  gtk = {
    enable = true;
    cursorTheme.name = "Adwaita";
    cursorTheme.package = pkgs.adwaita-icon-theme;
    theme.name = "adw-gtk3-light";
    theme.package = pkgs.adw-gtk3;
    iconTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "adwaita-icon-theme";
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      import = [ "${pkgs.alacritty-theme}/gruvbox_dark.toml" ];
      env = { XTERM_VERION = "9999"; };
      font = { size = 16; };
      font.normal = {
        family = "Noto Sans Mono";
        style = "Regular";
      };
      scrolling = { history = 10000; };
    };
  };

  xsession.enable = true;

  qt.enable = true;
  qt.platformTheme.name = "qtct";
  xdg.configFile."qt5ct/qt5ct.conf".text = ''
    [Appearance]
    icon_theme=breeze
  '';

  services.gnome-keyring.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs;
    [
      deluge
      obsidian
      wl-screenrec
      vlc
      xorg.xset # I see a vlc warning reguarding xset missing. Just in case.
      pavucontrol
      qpdf

      xfce.thunar

      zellij

      alacritty-theme
      wezterm

      sioyek
      eog
      seahorse # for keyring
      qimgv

      # inputs.nkitsaini_notes_utils.packages.${system}.default

      # I3 specific
      i3
      rofi
      pulseaudio
      playerctl
      brightnessctl

      # shows cp etc. progress
      progress

      # Xorg
      xorg.xev

      # From old fish history
      dolphin
      gparted
    ] ++ (if nixGLCommandPrefix != "" then
      [
        (writeShellApplication {
          name = "nixgl-run";
          text = ''
            exec ${nixGLCommandPrefix} -- "$@"
          '';
        })
      ]
    else
      [ ]);
}
