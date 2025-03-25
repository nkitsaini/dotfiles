{ pkgs, config, ... }: {
  home.packages = [ pkgs.tmux-sessionizer ];
  xdg.configFile."tms/config.toml".text = ''
    default_session = "${config.home.homeDirectory}/"
    display_full_path = true
    excluded_dirs = [
        "node_modules",
        "venv",
        ".venv",
        "target",
        ".direnv",
    ]

    [[search_dirs]]
    path = "${config.home.homeDirectory}/code"
    depth = 4

    [[search_dirs]]
    path = "${config.home.homeDirectory}/external"
    depth = 4

    [[search_dirs]]
    path = "${config.home.homeDirectory}/workspace"
    depth = 4
  '';
}
