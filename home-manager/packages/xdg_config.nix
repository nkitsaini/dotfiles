{pkgs, ...}: {
  
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
    }) browser_mimes);
    associations.added = builtins.listToAttrs (builtins.map (x: {
      name = x;
      # value = [ "${pkgs.firefox}/share/applications/firefox.desktop" ];
      value = [ "firefox.desktop" ];
    }) browser_mimes);
  };
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "/var/empty";
    publicShare = "/var/empty";
    documents = "documents";
    download = "downloads";
    music = "music";
    videos = "videos";
    pictures = "tmp";
    templates = "tmp";
  };
}
