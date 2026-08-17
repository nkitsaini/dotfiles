{ lib, pkgs, ... }: {
  home.packages = with pkgs; [

    # For yazi
    unar
    exiftool
    # mpv
    mediainfo
  ];
  programs.yazi.enable = true;
  programs.yazi.shellWrapperName = "yy";
  programs.yazi.settings = {
    opener = {
      system = [
        {
          run = "${lib.getExe' pkgs.glib "gio"} open %s";
          orphan = true;
          desc = "Open with default application";
          for = "unix";
        }
      ];
    };
    open = {
      prepend_rules = [
        {
          mime = "video/*";
          use = "system";
        }

        {
          mime = "audio/*";
          use = "system";
        }

        {
          mime = "image/*";
          use = "system";
        }

        {
          mime = "application/pdf";
          use = "system";
        }
      ];
    };
  };
}
