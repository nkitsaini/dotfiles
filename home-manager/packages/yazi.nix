{ pkgs, ... }: {
  home.packages = with pkgs; [

    # For yazi
    unar
    exiftool
    # mpv
    mediainfo
  ];
  programs.yazi.enable = true;
  programs.yazi.settings = {
    opener = { video = [{ exec = ''vlc "$1"''; }]; };
    open = {
      rules = [{
        mime = "video/*";
        use = "video";
      }];
    };
  };
}
