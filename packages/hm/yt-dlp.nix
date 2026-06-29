{
  # yt-dlp "<playlist-url>" --download-archive archive.txt -f 'ba/best'                                          -x                  --audio-format mp3  --audio-quality 0                --embed-metadata            --embed-thumbnail
  #                         ^-- incremental download |      ^ first try best-audio only, then try best overall   ^ extract audio     ^ convert to mp3    ^ with best quality (15 worst)   ^ keep album/artist stuff   ^ Keep thumbnail       
  # 
  # TODO: write a script that wraps yt-dlp and can automatically update if the last version installed is older then a few days.
  #      should use **nightly** as recommended by yt-dlp
  # pipx upgrade ...
  # yt-dlp "$@"

  # programs.yt-dlp.enable = true;
  # programs.yt-dlp.settings = {
  #   embed-thumbnail = true;
  #   embed-subs = true;
  #   sub-langs = "all";
  #   downloader = "aria2c";
  #   downloader-args = "aria2c:'-c -x8 -s8 -k1M'";
  # };

  # NOTE: yt-dlp here is the uv-wrapped `yt-dlp@latest` from setup-minimal.nix,
  # not `programs.yt-dlp`, so the config is written directly to avoid a binary
  # collision. yt-dlp still reads ~/.config/yt-dlp/config regardless.
  #
  # Prefer H.264 (AVC): this machine's AMD iGPU (Lucienne, VCN 2.x) has no
  # hardware AV1 decoder, so AV1 streams fall back to CPU decoding. Sorting by
  # vcodec:h264 keeps playback on the GPU. format-sort degrades gracefully when
  # H.264 isn't offered (unlike a hard -f filter).
  xdg.configFile."yt-dlp/config".text = ''
    -S vcodec:h264
  '';
}
