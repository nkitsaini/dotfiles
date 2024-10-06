# This is a nixos package (not home-manager)
{ username, pkgs, ... }:
let
  start_desktop_script = pkgs.writeScriptBin "start_desktop" ''
    #!${pkgs.dash}/bin/dash
    exec sway
  '';
in {
  # Random configuration required to make sway work
  imports = [ ./sway-knobs.nix ];

  # services.xserver.enable = true;
  environment.systemPackages = [
    start_desktop_script
    (pkgs.catppuccin-sddm.override {
      flavor = "mocha";
      # CustomBackground = true;
      background = (import ../../shared/wallpapers.nix).wallpaper3;
      loginBackground = false;
    })
    (pkgs.sddm-chili-theme.override {
      themeConfig = {
        blur = false;
        background = (import ../../shared/wallpapers.nix).wallpaper3;
        # AvatarPixelSize = 15;
      };
    })
    (pkgs.where-is-my-sddm-theme.override {
      variants = [ "qt5" ];
      themeConfig.General = {
        # ref: https://github.com/stepanzubkov/where-is-my-sddm-theme/blob/main/where_is_my_sddm_theme/example_configs/tree.conf
        background = (import ../../shared/wallpapers.nix).wallpaper3;
        backgroundFillMode = "aspect";
        passwordInputRadius = 10;
        blurRadius = 0;
        usersFontSize = 16;
        basicTextColor = "#ffffff";
        passwordInputBackground = "#60ffffff";
        passwordInputWidth = 0.2;
        passwordFontSize = 14;
        sessionsFontSize = 14;
        showUsersByDefault = true;
        showSessionsByDefault = true;
        # AvatarPixelSize = 0;
      };
    })
  ];

  # services.xserver.displayManager.setupCommands = ''$HOME/.xsession'';

  services.displayManager.sessionPackages = [ pkgs.sway ];

  # ref: https://github.com/teto/home/blob/25aae4d91222b45c173e01f0744bca96c0858af3/nixos/profiles/xserver.nix#L75

  services.xserver.enable = true;
  services.xserver.displayManager.lightdm = {
    enable = true;
    background = (import ../../shared/wallpapers.nix).wallpaper3;
  };

  # services.displayManager.sddm = {
  #   enable = true;
  #   wayland.enable = true;
  #   # theme = "where_is_my_sddm_theme_qt5";
  #   theme = "chili";
  #   # theme = "catppuccin-mocha";

  #   # i3 => x11
  #   # sway => wayland
  # };

  # https://discourse.nixos.org/t/sway-nixos-home-manager-conflict/20760/11
  programs.sway.enable = true;
  programs.sway.package = null;

  home-manager.users.${username} = import ../../hm/sway;
}
