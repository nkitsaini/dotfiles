{ pkgs, ... }: {
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto-safe";
      osd-bar = "no";
      border = "no";
    };
    bindings = {
     h=  "script-binding uosc/playlist";
    };
    scripts = with pkgs; [
      mpvScripts.mpris # support playerctl
      mpvScripts.thumbfast # Thumbnail generator. why not work with uosc?
      mpvScripts.uosc # gui
      mpvScripts.mpv-cheatsheet # ? for help[]
      # mpvScripts.visualizer
      mpvScripts.cutter # c to start cut, c to end cut -> file in same directory
      mpvScripts.autoload # load files from directory
      mpvScripts.vr-reversal
      mpvScripts.webtorrent-mpv-hook
      mpvScripts.quality-menu # change yt-dlp quality on fly

    ];
  };
}
