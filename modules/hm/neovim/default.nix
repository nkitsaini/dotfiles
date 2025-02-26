{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  options.kit.neovim = {
    enable = lib.mkEnableOption "Neovim setup";
  };

  config = lib.mkIf config.kit.neovim.enable {

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
  };
}
