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
      pkgs.wireplumber
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

    kit.services = {
      notes-sync = {
        enable = true;
        repositories = pkgs.lib.mkOptionDefault [
           "${config.home.homeDirectory}/workspace/notes"
        ];
      };
    };

    programs.fish.shellAliases.rebuild-system = "home-manager switch --flake ${homeDirectory}/code/dotfiles/#shifu";
  }
)
