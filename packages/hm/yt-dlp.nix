{
  # yt-dlp "<playlist-url>" --download-archive archive.txt -f 'ba/best'                                          -x                  --audio-format mp3  --audio-quality 0                --embed-metadata            --embed-thumbnail
  #                         ^-- incremental download |      ^ first try best-audio only, then try best overall   ^ extract audio     ^ convert to mp3    ^ with best quality (15 worst)   ^ keep album/artist stuff   ^ Keep thumbnail       
  # 
  programs.yt-dlp.enable = true;
  programs.yt-dlp.settings = {
    embed-thumbnail = true;
    embed-subs = true;
    sub-langs = "all";
    downloader = "aria2c";
    downloader-args = "aria2c:'-c -x8 -s8 -k1M'";
  };
}
