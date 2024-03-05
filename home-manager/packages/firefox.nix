{ config, system, pkgs, lib, enableNixGL, nkitsaini_helix, ... }: {
  programs.firefox.enable = true;

  # remove after this: https://bugzilla.mozilla.org/show_bug.cgi?id=259356

  programs.firefox.package = pkgs.firefox.override {
    # See nixpkgs' firefox/wrapper.nix to check which options you can use
    nativeMessagingHosts = [
      # Tridactyl native connector
      pkgs.tridactyl-native
    ];
  };

  # TODO: use absolute path to `hx`. It's not in nkitsaini_helix/bin/hx but in
  # home-manager-path/bin/hx
  xdg.configFile."tridactyl/tridactylrc".text = ''
    js tri.config.set("editorcmd", "${pkgs.wezterm}/bin/wezterm -e ${nkitsaini_helix.packages.${system}.default}/bin/hx")
    js tri.config.set("theme", "shydactyl")
    bind --mode=normal <C-V> mode ignore
  ''; 

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
