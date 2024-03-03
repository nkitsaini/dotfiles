{ config, pkgs, lib, enableNixGL, ... }: {
  programs.firefox.enable = true;

  # remove after this: https://bugzilla.mozilla.org/show_bug.cgi?id=259356


  programs.firefox.policies = {
    DefaultDownloadsDirectory = "\${home}/downloads";
  };

  programs.firefox.profiles."default".extensions =
    with config.nur.repos.rycee.firefox-addons; [
      ublock-origin
      tridactyl
      bitwarden
      dearrow
      sponsorblock
      rsshub-radar

      # Currently missing
      # tab-wrangler
      # feedbro
    ];
}
