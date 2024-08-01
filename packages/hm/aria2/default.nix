{
  programs.aria2 = {
    enable = true;
    extraConfig = builtins.readFile ./aria2.conf;
  };
}
