# Has everything except for desktop manager.
# It is good to be used in nixos or standalone home-manager for desktop setups.
{
  pkgs,
  nixGLCommandPrefix ? "",
  ...
}:
{
  imports = [
    ./setup-minimal.nix
    ./wezterm
    ./firefox
    ./mpv
    ./theme
    ./zed
    ./sioyek
    ./activity_watch
    ./meditation-bell
    ./emacs
  ];
  modules.editors.emacs = {
    enable = false; # This is broken, need to delete emacs config altogether
  };

  services.blueman-applet.enable = false; # Disabled as it enables auto-connect for some reason

  programs.alacritty = {
    enable = true;
    settings = {
      import = [ "${pkgs.alacritty-theme}/gruvbox_dark.toml" ];
      env = {
        XTERM_VERION = "9999";
      };
      font = {
        size = 16;
      };
      font.normal = {
        family = "Noto Sans Mono";
        style = "Regular";
      };
      scrolling = {
        history = 10000;
      };
    };
  };

  xsession.enable = true;

  services.gnome-keyring.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages =
    with pkgs;
    [
      elan

      # deluge
      obsidian

      ollama

      # For some reason ctrl-c not working, so can't stop recording
      # wl-screenrec

      wf-recorder

      vlc
      xorg.xset # I see a vlc warning reguarding xset missing. Just in case.
      pavucontrol
      qpdf

      xfce.thunar
      nautilus

      zellij
      zed-editor

      alacritty-theme
      wezterm

      eog
      seahorse # for keyring
      qimgv

      pandoc
      typst
      # https://github.com/NixOS/nixpkgs/issues/419942#issuecomment-3025623956
      # pypy3.override (y: { sqlite = sqlite.overrideAttrs (x: { configureFlags = x.configureFlags ++ ["--soname=legacy"];});})

      usbutils
      # inputs.nkitsaini_notes_utils.packages.${system}.default

      # I3 specific
      i3
      rofi
      pulseaudio
      playerctl
      brightnessctl

      # music player
      amberol

      # shows cp etc. progress
      progress

      transmission_4-qt6

      texliveMedium

      # Xorg
      xorg.xev

      vulkan-tools

      # Run appimage
      appimage-run

      # Easy drag and drop for tiling wm
      dragon-drop

      # From old fish history
      kdePackages.dolphin
      kdePackages.konsole
      gparted

      # Required for something in neovim/neorg
      imagemagick
    ]
    ++ (
      if nixGLCommandPrefix != "" then
        [
          (writeShellApplication {
            name = "nixgl-run";
            text = ''
              exec ${nixGLCommandPrefix} -- "$@"
            '';
          })
          (writeShellApplication {
            # Run using vulkan
            name = "nixgl-vulkan-run";
            text = ''
              exec env WLR_RENDERER=vulkan  ${pkgs.nixgl.nixVulkanIntel}/bin/nixVulkanIntel -- "$@"
            '';
          })
        ]
      else
        [ ]
    );
}
