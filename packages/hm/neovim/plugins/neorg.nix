{
  programs.nixvim = {
    keymaps = [
      {
        action = ":Neorg journal today<CR>";
        key = "<leader>jt";
        mode = [
          "n"
          "v"
        ];
      }
      {
        action = ":Neorg journal yesterday<CR>";
        key = "<leader>jy";
        mode = [
          "n"
          "v"
        ];
      }
      {
        action = ":Neorg journal tomorrow<CR>";
        key = "<leader>jn";
        mode = [
          "n"
          "v"
        ];
      }
      {
        action = ":Neorg journal custom<CR>";
        key = "<leader>jc";
        mode = [
          "n"
          "v"
        ];
      }
      {
        action.__raw = ''
          function()
                  local current = vim.wo.concealcursor
                  if current == 'nc' then
                      vim.wo.concealcursor = ""
                  else
                      vim.wo.concealcursor = 'nc'
                  end
                end'';
        key = "<leader>ct";
        mode = [
          "n"
          "v"
        ];
        options = {
          desc = "Toggle concealcursor between 'nc' (only show in insert/visual) vs '' (show on current line)";
        };
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
          notes = "~/code/notes/norg";
        };

        "core.dirman".config.default_workspace = "notes";

        "core.concealer".__empty = null;
        "core.summary".__empty = null;
        "core.text-objects".__empty = null; # TODO: setup keybindings
        "core.completion".config.engine = "nvim-cmp";

        "core.export".__empty = null;
        "core.export.markdown".__empty = null;
        "core.latex.renderer".__empty = null;
        "core.integrations.telescope" = {
          config = {
            insert_file_link = {
              # disable if slow
              show_title_preview = true;
            };
          };
        };
      };
    };
  };
}
