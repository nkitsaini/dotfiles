{ pkgs, ... }:
(let
  name = "Ankit Saini";
  email = "asaini@singlestore.com";
  username = "asaini";
  homeDirectory = "/home/${username}";
in {
  programs.git.userName = name;
  programs.git.userEmail = email;
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../common_home.nix ../../packages/i3.nix ];
}
)

