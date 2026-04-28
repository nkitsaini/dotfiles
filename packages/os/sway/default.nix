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

  environment.systemPackages = [
    start_desktop_script
  ];

  # greetd avoids the X11 server that LightDM needs, eliminating
  # DRM master contention that caused multi-minute blank screens
  # when starting Sway.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${pkgs.sway}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # # Previous LightDM config (X11-based, caused DRM contention with Sway)
  # services.xserver.enable = true;
  # services.xserver.displayManager.lightdm = {
  #   enable = true;
  #   background = (import ../../shared/wallpapers.nix).wallpaper3;
  # };

  # https://discourse.nixos.org/t/sway-nixos-home-manager-conflict/20760/11
  programs.sway.enable = true;
  programs.sway.package = null;

  home-manager.users.${username} = import ../../hm/sway;
}
