{ pkgs, ... }:
{
  programs.nixvim = {

    plugins.lsp = {
      enable = true;
      servers = {
        # ansiblels.enable = true;
        # bashls.enable = true;
        # dhall-lsp-server.enable = true;
        dockerls.enable = true;
        # elixirls.enable = true;
        gopls.enable = true;
        nixd.enable = true;
        # prismals.enable = true;
        # pyright.enable = true;
        tailwindcss.enable = true;
        # terraformls.enable = true;
        yamlls.enable = true;
        # leanls.enable = true;
        basedpyright.enable = true;
        rust-analyzer = {
          enable = true;
          installRustc = false;
          installCargo = false;
        };
        svelte.enable = true;
      };
    };

    plugins.lsp-format.enable = true;

    plugins.lspkind = {
      enable = true;
      cmp.enable = true;
    };
    plugins.luasnip = {
      enable = true;
    };
    plugins.cmp_luasnip.enable = true;
    extraPackages = with pkgs; [ fzf ];

    plugins.cmp = {
      enable = true;
      autoEnableSources = true;
      settings.snippet.expand = "function(args) require('luasnip').lsp_expand(args.body) end";
      settings.mapping = {
        __raw = ''
          cmp.mapping.preset.insert({
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-c>'] = cmp.mapping.abort(),
            ['<C-n>'] = cmp.mapping(cmp.mapping.select_next_item(), {'i', 'c'}),
            ['<C-p>'] = cmp.mapping(cmp.mapping.select_prev_item(), {'i', 'c'}),
            ['<CR>'] = cmp.mapping.confirm({ select = true }),
          })
        '';
      };
      # settings.mapping = {
      #   "<CR>" = "cmp.mapping.confirm({ select = true })";
      #   "<C-n>" = {
      #     action = "cmp.mapping(cmp.mapping.select_next_item()";
      #     modes = [
      #       "i"
      #       "c"
      #     ];
      #   };
      #   "<C-p>" = {
      #     action = "cmp.mapping(cmp.mapping.select_prev_item()";
      #     modes = [
      #       "i"
      #       "c"
      #     ];
      #   };
      #   "<Tab>" = {
      #     action = ''
      #       function(fallback)
      #         if cmp.visible() then
      #           cmp.select_next_item()
      #         else
      #           fallback()
      #         end
      #       end
      #     '';
      #     modes = [
      #       "i"
      #       "s"
      #     ];
      #   };
      # };
      settings.sources = [
        { name = "buffer"; }
        { name = "luasnip"; }
        { name = "nvim_lsp"; }
        { name = "path"; }
        # { name = "tmux"; }
        { name = "neorg"; }
      ];
    };

    plugins.cmp-buffer = {
      enable = true;
    };

    plugins.cmp-nvim-lsp = {
      enable = true;
    };
    plugins.cmp-nvim-lua = {
      enable = true;
    };

    plugins.cmp-path = {
      enable = true;
    };

    keymaps = [
      {
        mode = "n";
        key = "<leader>lf";
        action = ":lua vim.lsp.buf.format()<CR>";
        #    lua = true;
        options = {
          silent = true;
          desc = "Format";
        };
      }
    ];
  };
}
