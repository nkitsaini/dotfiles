{ inputs, pkgs, ... }:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
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
    '';

  };
}
