{
  programs.nixvim = {
    extraConfigLua = ''
      -- ----------------- neorg.dirman monkey patching start ------------------
      -- 
      -- https://github.com/nvim-neorg/neorg/blob/bdb29ea3e069f827d31973bc942c18793ee9fa64/lua/neorg/modules/core/dirman/module.lua#L415
      -- 
      local dirman = require('neorg').modules.get_module("core.dirman")

      -- Monkey Patching: Adds a filter to not scan hidden directories
      local new_get_norg_files = function(workspace_name)
      	local res = {}
      	local workspace = dirman.get_workspace(workspace_name)

      	if not workspace then
      		return
      	end

      	local path_filter = function(path)
      		return path:is_hidden()
      	end

      	for path in workspace:fs_iterdir(true, 20, path_filter) do
      		if path:is_file(true) and path:suffix() == ".norg" then
      			table.insert(res, path)
      		end
      	end

      	return res
      end
      dirman.get_norg_files = new_get_norg_files;

      -- :---------------- neorg.dirman monkey patching end ------------------

    '';
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
      telescopeIntegration.enable = true;
      modules = {
        "core.defaults".__empty = null;

        "core.keybinds".config.hook.__raw = ''
          function(keybinds)
            keybinds.unmap('norg', 'n', '<C-s>')
          end
        '';

        "core.dirman".config = {
          workspaces = {
            notes = "~/code/notes/";
          };
          open_last_workspace = "default";
          default_workspace = "notes";
        };

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
