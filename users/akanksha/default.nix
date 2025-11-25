{ hostname, ... }:
let
  name = "Akanksha Saini";
  email = "akankshasaini03@gmail.com";
  username = import ./username.nix;
  homeDirectory = "/home/${username}";
in {
  home-manager.users.${username} = {
    home.username = username;
    home.homeDirectory = homeDirectory;

    programs.git.settings.user.name = name;
    programs.git.settings.user.email = email;
    programs.jujutsu.settings.user.name = name;
    programs.jujutsu.settings.user.email = email;
    programs.fish.shellAliases.rebuild-system =
      "sudo nixos-rebuild switch --flake ${homeDirectory}/code/dotfiles/#${hostname}";
  };

  # Avoid typing the username on TTY and only prompt for the password
  # https://wiki.archlinux.org/title/Getty#Prompt_only_the_password_for_a_default_user_in_virtual_console_login
  services.getty.loginOptions = "-p -- ${username}";
  services.getty.extraArgs = [ "--noclear" "--skip-login" ];

  users.users.${username} = {
    uid = 1000;
    description = name;
    isNormalUser = true;

    # mkpasswd -m sha-512 <password>
    hashedPassword =
      "$6$8fsjkjSExwsNGZ/M$1qdlgwGpbX8mkJh8EPCJx5VI.A0tN0tSVeV5HaAo6f76EJjxzJ/OhXX4Aa5uBSEogHBU7c4oQ3qGjbxABDBSg/";

    openssh.authorizedKeys.keys = import ../../packages/authorized_keys.nix;
    extraGroups = [ "wheel" "input" "docker" "video" "networkmanager" ];
  };
}
