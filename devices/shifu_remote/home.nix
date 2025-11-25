{ pkgs, ... }:
(let
  name = "Ankit Saini";
  email = "asaini@singlestore.com";
  username = "asaini";
  homeDirectory = "/home/${username}";
in {
  programs.git.settings.user.name = name;
  programs.git.settings.user.email = email;
  programs.jujutsu.settings.user.name = name;
  programs.jujutsu.settings.user.email = email;
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../../packages/hm/setup-minimal.nix ];

  targets.genericLinux.enable = true;

  programs.fish.shellAliases.rebuild-system =
    "home-manager switch --flake ${homeDirectory}/code/dotfiles/#shifu_remote";
  programs.fish.shellInit = pkgs.lib.mkAfter ''
    sudo sysctl -w fs.inotify.max_user_instances=8192
  '';

  home.file.".vnc/startup" = {
    text = ''
      #!/bin/sh
      unset SESSION_MANAGER
      unset DBUS_SESSION_BUS_ADDRESS
      startxfce4
    '';
    executable=true;
  };
  # ----------- remote connection ------------
  home.packages = with pkgs; [
    firefox
    tigervnc
    xfce.xfce4-session
    xfce.xfce4-panel
    xfce.xfdesktop
    xfce.xfwm4
  ];
})
