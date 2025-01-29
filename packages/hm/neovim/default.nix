{ inputs, pkgs, ... }:
{
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    ./plugins
  ];
  programs.nixvim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };
    opts = {
      number = true;
      foldlevel = 99;
      conceallevel = 2;
      concealcursor = "";
      linebreak = true;
      breakindent = true;
      signcolumn = "yes";
      timeoutlen = 200;
    };

    performance = {
      byteCompileLua.enable = true;

      # Add any plugin here if it gives collisions
      # while nix build
      # see: https://nix-community.github.io/nixvim/performance/combinePlugins.html#performancecombinepluginsenable
      combinePlugins = {
        enable = true;
        standalonePlugins = [
          "hmts.nvim"
          "neorg"
          "nvim-treesitter"
          "orgmode"
          # "lualine"
        ];
      };
    };

    luaLoader.enable = true;
    colorschemes = {
      gruvbox.enable = true;
      tokyonight.enable = true;
      ayu.enable = true;
      one.enable = true;
      onedark.enable = true;

      # vscode.enable = true;
      catppuccin.enable = true;

      everforest.enable = true;
      dracula.enable = true;
      dracula-nvim.enable = true;
      nord.enable = true;
    };
    colorscheme = pkgs.lib.mkForce "everforest";
    extraConfigLua = ''
      -- see :help everforest.txt (search "custom colors")
      -- and :Telescope highlights
      local function everforest_custom()
          for i = 1, 6 do
              local base = '@neorg.headings.' .. i
              local markdown = 'markdownH' .. i
              vim.api.nvim_set_hl(0, base .. '.prefix', { link = markdown })
              vim.api.nvim_set_hl(0, base .. '.title', { link = markdown })
          end
      end

      -- Set up the autocommand
      vim.api.nvim_create_autocmd("ColorScheme", {
          pattern = "everforest",
          callback = everforest_custom,
          group = vim.api.nvim_create_augroup("EverforestCustom", { clear = true })
      })
    '';

  };
}

/*
  programs.neovim = {
    enable = true;
    vimAlias = true;
    plugins = [
      pkgs.vimPlugins.copilot-vim
      pkgs.vimPlugins.vim-fugitive
      pkgs.vimPlugins.neogit
      pkgs.vimPlugins.tokyonight-nvim
      pkgs.vimPlugins.diffview-nvim
      pkgs.vimPlugins.telescope-nvim
      pkgs.vimPlugins.which-key-nvim
      pkgs.vimPlugins.plenary-nvim
      pkgs.vimPlugins.obsidian-nvim
      pkgs.vimPlugins.orgmode
      pkgs.vimPlugins.nvim-cmp
      pkgs.vimPlugins.neorg
      # pkgs.vimPlugins.vim-markdown
    ];
    extraLuaConfig = ''
      local neogit = require('neogit')
      neogit.setup {}

      vim.g.mapleader = ' '
      vim.opt.termguicolors = true
      vim.cmd 'colorscheme tokyonight-storm'

      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
      vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
      vim.print("Config done")
      vim.opt.number = true

      -- Which Key
      vim.o.timeout = true
      vim.o.timeoutlen = 300
      require("which-key").setup {}
      require("obsidian").setup({
        workspaces = {
          {
            name ="notes",
            path="~/code/notes"
          }
        }
      })

      -- Org Mode
      require('orgmode').setup({
        org_agenda_files = '~/code/notes/org/** /*', <-- remove one space
        org_default_notes_file = '~/code/notes/org/main.org',
      })
      require('cmp')

      -- neorg
      require('neorg').setup()

    '';
  };
*/
