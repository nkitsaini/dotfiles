{ pkgs, ... }:
{
  programs.nixvim = {

    plugins.lsp = {
      enable = true;
      servers = {
        ansiblels.enable = true;
        bashls.enable = true;
        dhall-lsp-server.enable = true;
        dockerls.enable = true;
        elixirls.enable = true;
        gopls.enable = true;
        nixd.enable = true;
        prismals.enable = true;
        # pyright.enable = true;
        tailwindcss.enable = true;
        terraformls.enable = true;
        yamlls.enable = true;
        leanls.enable = true;
        basedpyright.enable = true;
        rust_analyzer.enable = true;
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

    plugins.nvim-cmp = {
      enable = true;
      # snippet.expand = "function(args) require('luasnip').lsp_expand(args.body) end";
      # mapping = {
      #   "<CR>" = "cmp.mapping.confirm({ select = true })";
      #   "<Tab>" = {
      #     action = ''
      #       function(fallback)
      #       if cmp.visible() then
      #       cmp.select_next_item()
      #       else
      #       fallback()
      #       end
      #       end
      #     '';
      #     modes = [
      #       "i"
      #       "s"
      #     ];
      #   };
      # };
      # sources = [
      #   { name = "buffer"; }
      #   { name = "luasnip"; }
      #   { name = "nvim_lsp"; }
      #   { name = "path"; }
      #   { name = "tmux"; }
      # ];
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
