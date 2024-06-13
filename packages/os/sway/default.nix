# This is a nixos package (not home-manager)
{ username, pkgs, ... }: {

  # Random configuration required to make sway work
  imports = [ ./sway-knobs.nix ];

  # services.xserver.enable = true;
  environment.systemPackages = [
    (pkgs.writeScriptBin "start_desktop" ''
      #!${pkgs.dash}/bin/dash
      $HOME/.xsession && sway
    '')

    
  ];

  # ref: https://github.com/teto/home/blob/25aae4d91222b45c173e01f0744bca96c0858af3/nixos/profiles/xserver.nix#L75
  # services.displayManager.sddm = {
  #   enable = true;
  #   wayland.enable = true;

  #   # i3 => x11
  #   # sway => wayland
  # };


  # https://discourse.nixos.org/t/sway-nixos-home-manager-conflict/20760/11
  programs.sway.enable = true;
  programs.sway.package = null;

  home-manager.users.${username} = import ../../hm/sway;
}
