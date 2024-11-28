{ pkgs, ... }:
{
  imports = [
    ./telescope.nix
    ./treesitter.nix
    ./neorg.nix
    ./neo-tree.nix
    ./nvim-cmp.nix
  ];
  programs.nixvim = {
    plugins = {
      which-key = {
        enable = true;
        settings = {
          delay = 200;
        };
      };
      typescript-tools.enable = true;
      auto-save.enable = true;
    };
  };

  home.packages = [
    pkgs.typescript
  ];
}
