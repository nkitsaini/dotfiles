{ pkgs, ... }: {

  xdg.enable = true;
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps = let
    browser_mimes = [
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/chrome"
      "text/html"
      "application/x-extension-htm"
      "application/x-extension-html"
      "application/x-extension-shtml"
      "application/xhtml+xml"
      "application/x-extension-xhtml"
      "application/x-extension-xht"
    ];
  in {
    enable = true;
    defaultApplications = builtins.listToAttrs (builtins.map (x: {
      name = x;
      # value = "${pkgs.firefox}/share/applications/firefox.desktop";
      value = "firefox.desktop";
    }) browser_mimes) // {
      "inode/directory" = "yazi.desktop";
      "image/jpeg" = "qimgv.desktop";
      "image/jpg" = "qimgv.desktop";
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
      categories = [ "Application" "Utility" ];
      mimeType = [ "inode/directory" ];
    };
  };
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "Desktop";
    publicShare = "share";
    documents = "Documents";
    download =
      "Downloads"; # firefox doesn't respect this, so using upper case stuff!
    music = "Music"; # I think some one doesn't respect this
    videos = "videos";
    pictures = "pictures";
    templates = "tmp";
  };
}
