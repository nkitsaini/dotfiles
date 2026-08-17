{ lib, pkgs, ... }:
let
  browserMimes = [
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/chrome"
    "text/html"
    "text/xml"
    "application/xml"
    "application/xhtml+xml"
    "application/vnd.mozilla.xul+xml"
    "application/x-extension-htm"
    "application/x-extension-html"
    "application/x-extension-shtml"
    "application/x-extension-xhtml"
    "application/x-extension-xht"
  ];

  audioMimes = [
    "application/ogg"
    "application/x-extension-m4a"
    "application/x-flac"
    "application/xspf+xml"
    "audio/3gpp"
    "audio/3gpp2"
    "audio/aac"
    "audio/ac3"
    "audio/aiff"
    "audio/amr"
    "audio/amr-wb"
    "audio/basic"
    "audio/eac3"
    "audio/flac"
    "audio/m4a"
    "audio/midi"
    "audio/mp1"
    "audio/mp2"
    "audio/mp3"
    "audio/mp4"
    "audio/mpeg"
    "audio/mpegurl"
    "audio/mpg"
    "audio/ogg"
    "audio/opus"
    "audio/scpls"
    "audio/vnd.dolby.heaac.1"
    "audio/vnd.dolby.heaac.2"
    "audio/vnd.dts"
    "audio/vnd.dts.hd"
    "audio/vnd.rn-realaudio"
    "audio/vnd.wave"
    "audio/vorbis"
    "audio/wav"
    "audio/webm"
    "audio/x-aac"
    "audio/x-adpcm"
    "audio/x-aiff"
    "audio/x-ape"
    "audio/x-flac"
    "audio/x-m4a"
    "audio/x-matroska"
    "audio/x-mp1"
    "audio/x-mp2"
    "audio/x-mp3"
    "audio/x-mpeg"
    "audio/x-mpegurl"
    "audio/x-mpg"
    "audio/x-ms-asf"
    "audio/x-ms-wma"
    "audio/x-musepack"
    "audio/x-pn-aiff"
    "audio/x-pn-au"
    "audio/x-pn-realaudio"
    "audio/x-pn-wav"
    "audio/x-realaudio"
    "audio/x-scpls"
    "audio/x-shorten"
    "audio/x-speex"
    "audio/x-tta"
    "audio/x-vorbis"
    "audio/x-vorbis+ogg"
    "audio/x-wav"
    "audio/x-wavpack"
  ];

  videoMimes = [
    "application/mxf"
    "application/vnd.apple.mpegurl"
    "application/vnd.ms-asf"
    "application/vnd.rn-realmedia"
    "application/vnd.rn-realmedia-vbr"
    "application/x-extension-mp4"
    "application/x-matroska"
    "video/3gp"
    "video/3gpp"
    "video/3gpp2"
    "video/avi"
    "video/divx"
    "video/dv"
    "video/fli"
    "video/flv"
    "video/mkv"
    "video/mp2t"
    "video/mp4"
    "video/mp4v-es"
    "video/mpeg"
    "video/msvideo"
    "video/ogg"
    "video/quicktime"
    "video/vnd.avi"
    "video/vnd.divx"
    "video/vnd.mpegurl"
    "video/vnd.rn-realvideo"
    "video/webm"
    "video/x-avi"
    "video/x-flc"
    "video/x-flic"
    "video/x-flv"
    "video/x-m4v"
    "video/x-matroska"
    "video/x-mpeg2"
    "video/x-mpeg3"
    "video/x-ms-afs"
    "video/x-ms-asf"
    "video/x-msvideo"
    "video/x-ms-wmv"
    "video/x-ms-wmx"
    "video/x-ms-wvxvideo"
    "video/x-ogm"
    "video/x-ogm+ogg"
    "video/x-theora"
    "video/x-theora+ogg"
  ];

  imageMimes = [
    "image/bmp"
    "image/gif"
    "image/jpeg"
    "image/png"
    "image/webp"
  ];

  textMimes = [
    "application/x-zerosize"
    "text/plain"
    "text/markdown"
    "text/x-markdown"
    "text/x-readme"
    "text/x-log"
    "text/csv"
    "text/tab-separated-values"
    "application/json"
    "application/ld+json"
    "application/x-yaml"
    "text/yaml"
    "application/toml"
    "text/x-ini"
    "text/x-properties"
    "application/x-shellscript"
    "text/x-shellscript"
    "text/x-python"
    "text/x-python3"
    "text/x-script.python"
    "text/x-csrc"
    "text/x-chdr"
    "text/x-c++src"
    "text/x-c++hdr"
    "text/x-java"
    "text/x-java-source"
    "application/javascript"
    "application/x-javascript"
    "text/javascript"
    "application/typescript"
    "text/x-go"
    "text/rust"
    "text/x-rust"
    "text/x-ruby"
    "application/x-ruby"
    "application/x-perl"
    "text/x-perl"
    "application/x-php"
    "text/x-php"
    "text/x-lua"
    "text/x-haskell"
    "text/x-erlang"
    "text/x-elixir"
    "text/x-clojure"
    "text/x-scheme"
    "text/x-lisp"
    "text/x-swift"
    "text/x-kotlin"
    "text/x-scala"
    "text/x-sql"
    "application/sql"
    "text/x-dockerfile"
    "application/x-dockerfile"
    "text/x-makefile"
    "text/x-cmake"
    "text/x-nix"
    "application/x-nix"
    "text/x-diff"
    "text/x-patch"
    "text/x-tex"
    "text/x-bibtex"
    "text/x-po"
  ];
in
{

  xdg.enable = true;

  # KService needs a root menu to discover applications outside Plasma.
  # Without this Dolphin falls back to an unavailable app-chooser portal.
  xdg.configFile."menus/applications.menu".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN" "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
    <Menu>
      <Name>Applications</Name>
      <DefaultAppDirs/>
      <DefaultDirectoryDirs/>
      <MergeDir>applications-merged</MergeDir>
      <DefaultLayout>
        <Merge type="menus"/>
        <Merge type="files"/>
      </DefaultLayout>
    </Menu>
  '';

  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      lib.genAttrs browserMimes (_: "firefox.desktop")
      // lib.genAttrs audioMimes (_: "vlc.desktop")
      // lib.genAttrs videoMimes (_: "mpv.desktop")
      // lib.genAttrs imageMimes (_: "qimgv.desktop")
      // lib.genAttrs textMimes (_: "dev.zed.Zed.desktop")
      // {
        "application/pdf" = "sioyek.desktop";
        "application/epub+zip" = "sioyek.desktop";
        "inode/directory" = "org.kde.dolphin.desktop";
      };
  };

  xdg.desktopEntries = {
    yazi = {
      name = "Yazi";
      genericName = "File Browser";
      exec = "${pkgs.yazi}/bin/yazi %f";
      # tryExec = "${pkgs.yazi}/bin/yazi";
      icon = "Folder";
      terminal = true;
      categories = [
        "Application"
        "Utility"
      ];
      mimeType = [ "inode/directory" ];
    };
  };
  xdg.userDirs = {
    enable = true;
    setSessionVariables = true;
    createDirectories = true;
    desktop = "Desktop";
    publicShare = "share";
    documents = "Documents";
    download = "Downloads"; # firefox doesn't respect this, so using upper case stuff!
    music = "music"; # I think some one doesn't respect this
    videos = "videos";
    pictures = "pictures";
    templates = "tmp";
  };
}
