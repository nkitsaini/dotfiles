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
    opener = {
      video = [{ exec = ''mpv -d "$1"''; }];
      audio = [{ exec = ''mpv -d "$1"''; }];
    };
    open = {
      rules = [
        {
          mime = "video/*";
          use = "video";
        }

        {
          mime = "audio/*";
          use = "audio";
        }
      ];
    };
  };
}
