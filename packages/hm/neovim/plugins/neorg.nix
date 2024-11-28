{
  programs.nixvim = {
    keymaps = [
      {
        action = ":Neorg journal today<CR>";
        key = "<leader>jt";
        mode = ["n" "v"];
      }
      {
        action = ":Neorg journal yesterday<CR>";
        key = "<leader>jy";
        mode = ["n" "v"];
      }
      {
        action = ":Neorg journal tomorrow<CR>";
        key = "<leader>jn";
        mode = ["n" "v"];
      }
      {
        action = ":Neorg journal custom<CR>";
        key = "<leader>jc";
        mode = ["n" "v"];
      }
    ];
    plugins.neorg = {
      enable = true;
      modules = {
        "core.defaults".__empty = null;

        "core.keybinds".config.hook.__raw = ''
          function(keybinds)
            keybinds.unmap('norg', 'n', '<C-s>')
          end
        '';

        "core.dirman".config.workspaces = {
          notes = "~/code/notes/neorg";
        };

        "core.dirman".config.default_workspace = "notes";

        "core.concealer".__empty = null;
        "core.ui".__empty = null;
        "core.ui.calendar".__empty = null;
        # "core.completion".__empty = null;
        "core.completion".config.engine = "nvim-cmp";
        "core.todo-introspector".__empty = null;
        # "core.completion".configuration.engine = "nvim-cmp";
      };
    };
  };
}
