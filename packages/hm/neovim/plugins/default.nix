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
      markdown-preview.enable = true;
      image.enable = true;
      web-devicons.enable = true; # is dependency of something, gives warning if not added, can be removed safely
      # lualine.enable = true;


      orgmode = {
        enable = true;
        settings = {
          org_agenda_files = "~/code/notes/org/**/*";
          org_default_notes_file = "~/code/notes/org/index.org";
        };
      };
    };
  };

  home.packages = [
    pkgs.typescript
  ];
}
