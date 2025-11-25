{ hostname, ... }:
let
  name = "Ankit Saini";
  email = "nnkitsaini@gmail.com";
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
      "$6$Z1Ak/SkICKwL2tLN$THztROB935o87EQUkRzZlD0xrszPx5L/X5SA6ePv0v0bgGzJN2PnLbJ8FJe.iqXtb8BPl1kj/8N7OGblvY5sY1";

    openssh.authorizedKeys.keys = import ../../packages/authorized_keys.nix;
    extraGroups = [ "wheel" "input" "docker" "video" "networkmanager" ];
  };
}
