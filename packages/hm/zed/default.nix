{
  pkgs,
  nixGLCommandPrefix ? "",
  ...
}:
{
  # Zed's CLI spells this `--new` (not `--new-window`). Keep the process
  # attached until the opened file is closed so terminal callers can resume.
  home.sessionVariables.EDITOR = "zed --new --wait";

  programs.zed-editor = {
    enable = true;
    package = null; # Installed through the nixGL-aware package setup below.

    # kit.mutableConfig's merge strategy mostly mirrors Zed's built-in mutable
    # mode. If it causes trouble, re-enable this and use trackOnly for diffing.
    mutableUserSettings = false;

    userSettings = {
      cli_default_open_behavior = "new_window";
      project_panel.dock = "left";
      # Only affects workspaces Zed has no remembered panel state for (every
      # `capture` session is a fresh directory). Existing projects still
      # restore whatever dock layout they were last closed with.
      project_panel.starts_open = false;
      outline_panel.dock = "left";
      collaboration_panel.dock = "left";

      git_panel = {
        group_by = "none";
        dock = "left";
        tree_view = true;
      };

      edit_predictions = {
        provider = "copilot";
        mode = "eager";
      };

      agent = {
        dock = "right";
        play_sound_when_agent_done = "always";
      };

      format_on_save = "off";
      languages = {
        Go.format_on_save = "on";
        Markdown = {
          language_servers = [ "vtsls" ];
          format_on_save = "off";
          document_folding_ranges = "on";
          formatter.language_server.name = "vtsls";
        };
      };

      ui_font_size = 16;
      buffer_font_size = 16;
      theme = {
        light = "Gruvbox Light Hard";
        dark = "Gruvbox Dark Hard";
        mode = "system";
      };
      vim_mode = true;
      buffer_font_family = "Noto Mono";
      autosave = "on_focus_change";

      lsp = {
        # zed does not provide a way to define custom lsp: https://github.com/zed-industries/zed/discussions/24092
        # override an unused one
        vtsls.binary = {
          path = "sanemark";
          arguments = [ ];
        };
      };

      feature_flags = {
        tabular-data-preview = "on";
        notebooks = "on";
      };
    };
  };

  kit.mutableConfig.files.".config/zed/settings.json" = {
    strategy = "merge";
    mergeFormat = "json5";
  };

  home.packages =
    with pkgs;
    [
      zed-editor

      # Nix support
      nil
      nixd
      marksman
    ]
    ++ (
      if nixGLCommandPrefix != "" then
        [
          (writeShellApplication {
            name = "zed";
            text = ''
              exec nixgl-vulkan-run ${pkgs.zed-editor}/bin/zeditor "$@"
            '';
          })
        ]
      else
        [
          (writeShellApplication {
            name = "zed";
            text = ''
              exec ${pkgs.zed-editor}/bin/zeditor "$@"
            '';
          })
        ]
    );

}
