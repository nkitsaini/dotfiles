{
  programs.yt-dlp.enable = true;
  programs.yt-dlp.settings = {
    embed-thumbnail = true;
    embed-subs = true;
    sub-langs = "all";
    downloader = "aria2c";
    downloader-args = "aria2c:'-c -x8 -s8 -k1M'";
  };
}
