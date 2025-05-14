{ config, system, pkgs, inputs, ... }:
let
  # Allow key overrides like <Ctrl+t> in firefox for default
  # bindings
  firefox_patched = pkgs.firefox.overrideAttrs (oldAttrs: {
    buildInputs = oldAttrs.buildInputs ++ [ pkgs.perl ];
    buildCommand = oldAttrs.buildCommand + ''
      perl -i -pne 's/reserved="true"/               /g' $out/lib/firefox/browser/omni.ja
    '';
  });
in {
  programs.firefox.enable = true;

  home.packages = with pkgs; [ xdg-desktop-portal-xapp xdg-desktop-portal-gtk ];

  programs.firefox.package = firefox_patched.override {
    # See nixpkgs' firefox/wrapper.nix to check which options you can use
    nativeMessagingHosts = [
      # Tridactyl native connector
      pkgs.tridactyl-native
    ];
  };

  # TODO: use absolute path to `hx`. It's not in helix_master/bin/hx but in
  # home-manager-path/bin/hx
  xdg.configFile."tridactyl/tridactylrc".text = ''
    js tri.config.set("editorcmd", "${pkgs.wezterm}/bin/wezterm -e hx")
    js tri.config.set("theme", "shydactyl")
    bind --mode=normal <C-V> mode ignore
    unbind --mode=normal <C-f>
  '';
  xdg.configFile."tridactyl/autoclose.js".source = pkgs.runCommand "tridactyl-autoclose-build" {} "${pkgs.bun}/bin/bun build ${./tridactyl_autoclose.ts} --outfile=$out";

  # remove after this: https://bugzilla.mozilla.org/show_bug.cgi?id=259356
  programs.firefox.policies = {
    # TODO: move everyone to `~/Downloads`, some tools just want to write to `~/Downloads` irrespective of your wish
    DefaultDownloadsDirectory = "\${home}/downloads";
  };

  programs.firefox.profiles."default" = {
    settings = {
     "sidebar.revamp" = true; 
     "sidebar.verticalTabs" = true; 
    };
    # containers = {
    #   personal = {
    #     color = "orange";
    #     icon = "fruit";
    #     id = 1;
    #   };
    #   random = {
    #     color = "yellow";
    #     icon = "cart";
    #     id = 2;
    #   };
    # };
    extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
      ublock-origin
      tridactyl
      bitwarden
      dearrow
      sponsorblock
      rsshub-radar
      multi-account-containers

      # Currently missing
      # tab-wrangler
      # feedbro
    ];
  };
}
