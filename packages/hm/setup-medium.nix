# Has everything except for desktop manager.
# It is good to be used in nixos or standalone home-manager for desktop setups.
{
  pkgs,
  inputs,
  nixGLCommandPrefix ? "",
  ...
}:
{
  imports = [
    ./setup-minimal.nix
    ./firefox
    ./mpv
    ./theme
    ./darkmode
    ./zed
    ./sioyek
    ./activity_watch
    ./meditation-bell
    ./camera-ctl
  ];

  kit.programs.ghostty.enable = true;
  kit.blocks = {
    agentic-coding.enable = true;
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

      # has gsettings (useful for prefers-dark/light settings)
      glib

      vlc
      xset # I see a vlc warning reguarding xset missing. Just in case.
      pavucontrol
      qpdf

      thunar
      nautilus

      zellij
      zed-editor

      alacritty-theme

      v4l-utils

      unrar
      # csv wrangler
      xan

      eog
      seahorse # for keyring
      qimgv

      pandoc
      typst
      # https://github.com/NixOS/nixpkgs/issues/419942#issuecomment-3025623956
      # pypy3.override (y: { sqlite = sqlite.overrideAttrs (x: { configureFlags = x.configureFlags ++ ["--soname=legacy"];});})

      usbutils

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
      xev

      vulkan-tools

      # Run appimage
      appimage-run

      # Easy drag and drop for tiling wm
      dragon-drop

      # From old fish history
      kdePackages.dolphin
      kdePackages.konsole
      gparted

      # Markdown language server (built from ./softwares/markdown_lsp).
      inputs.markdown_lsp.packages.${pkgs.stdenv.hostPlatform.system}.default

      # radioctl TUI (built from ./softwares/radioctl).
      inputs.radioctl.packages.${pkgs.stdenv.hostPlatform.system}.default

      # karo: one front-end for every task runner (built from ./softwares/karo).
      inputs.karo.packages.${pkgs.stdenv.hostPlatform.system}.default
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
