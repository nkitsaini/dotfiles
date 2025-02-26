{ pkgs, config, ... }:
let
  norg-meta-plugin = import ./packages/tree-sitter-norg-meta.nix { inherit pkgs; };
in
{

  programs.nixvim = {
    # extraPlugins = [
    #   norg-meta-plugin
    # ];

    plugins = {
      treesitter = {
        enable = true;

        nixvimInjections = true;

        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
        folding = true;
        grammarPackages = config.programs.nixvim.plugins.treesitter.package.passthru.allGrammars ++ [
          norg-meta-plugin
        ];
      };

      treesitter-refactor = {
        enable = true;
        highlightDefinitions = {
          enable = true;
          # Set to false if you have an `updatetime` of ~100.
          clearOnCursorMove = false;
        };
      };

      hmts.enable = true;
    };
  };
}
