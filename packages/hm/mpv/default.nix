{pkgs, ...}: {
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto-safe";
      osd-bar = "no";
      # osc = "no";
      border = "no";
    };
    bindings = {
      h = "script-binding uosc/playlist";
    };
    scriptOpts = {
      uosc = {
        timeline_style = "bar";
        opacity = "timeline=1,position=1,chapters=1,slider=1,slider_gauge=1,controls=1,speed=1,menu=1,submenu=1,border=1,title=1,tooltip=1,thumbnail=1,curtain=1,idle_indicator=1,audio_indicator=1,buffering_indicator=1,playlist_position=1";
        
        # disable proximity
        proximity_in = 100000;
        proximity_out = 100000;
        autohide = "yes";
      };
    };
    scripts = with pkgs; [
      mpvScripts.mpris # support playerctl
      mpvScripts.thumbfast # Thumbnail generator. why not work with uosc?
      mpvScripts.uosc # gui
      # mpvScripts.modernx # gui
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
