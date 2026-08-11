{ pkgs, config, ... }:
(
  let
    name = "Ankit Saini";
    email = "asaini@singlestore.com";
    username = "asaini";
    homeDirectory = "/home/${username}";
  in
  {
    programs.git.settings.user.name = name;
    programs.git.settings.user.email = email;
    programs.jujutsu.settings.user.name = name;
    programs.jujutsu.settings.user.email = email;
    home.username = username;
    home.homeDirectory = homeDirectory;
    imports = [
      ../../packages/hm/setup-full.nix
      ../../packages/hm/sway
    ];
    home.packages = [
      pkgs.slack
      pkgs.nixgl.nixVulkanIntel
      pkgs.nixgl.nixGLIntel
      # wpctl only — full pkgs.wireplumber puts share/wireplumber ahead of
      # Ubuntu's on XDG_DATA_DIRS, so the system wireplumber binary loads
      # nixpkgs scripts and crashes (PermissionManager / exit 78).
      (pkgs.runCommand "wpctl" { } ''
        mkdir -p $out/bin
        ln -s ${pkgs.wireplumber}/bin/wpctl $out/bin/wpctl
      '')
      pkgs.awscli2
      pkgs.code-cursor
      pkgs.cursor-cli
      pkgs.mariadb.client
      pkgs.cloudflared
      pkgs.hubble
      pkgs.entr
      pkgs.dbeaver-bin
    ];
    xdg.mimeApps.associations.added = {
      "x-scheme-handler/slack" = [ "slack.desktop" ];
    };
    targets.genericLinux.enable = true;

    # "work" is the container with the real cookie jar (userContextId 12);
    # a second empty container named "Work" also exists - don't rename this
    # to it (matching is exact-first, see kit_containers.sys.mjs).
    kit.firefox.defaultContainer = "work";
    kit.programs.capture = {
      enable = true;
      sessionsDirectory = "${homeDirectory}/workspace/notes/sessions";
    };

    kit.rebuild = {
      enable = true;
      kind = "home-manager";
      attribute = "shifu";
    };

    kit.services = {
      notes-sync = {
        enable = true;
        repositories = pkgs.lib.mkOptionDefault [
          "${config.home.homeDirectory}/workspace/notes"
        ];
      };
    };
  }
)
