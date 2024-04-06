{ config, pkgs, inputs, system, ... }: {
  programs.helix = let
    comment_binding = '':pipe ${config.home.homeDirectory}/code/commenter/target/release/commenter --start-comment-token="/*" --end-comment-token="*/"'';
  in {
    enable = true;
    package = inputs.nkitsaini_helix.packages.${system}.default;
    defaultEditor = true;
    extraPackages = [
      pkgs.marksman
      pkgs.nil
      pkgs.texlab
      pkgs.gopls
      pkgs.golangci-lint-langserver
      pkgs.rust-analyzer
      pkgs.typst-lsp
      pkgs.biome
      pkgs.nodePackages.pyright
      pkgs.dockerfile-language-server-nodejs
      pkgs.nodePackages.vscode-css-languageserver-bin
      pkgs.nodePackages.vscode-json-languageserver-bin
      pkgs.nodePackages.vscode-html-languageserver-bin
      pkgs.nodePackages.typescript-language-server
      pkgs.nodePackages.svelte-language-server
      pkgs.tailwindcss-language-server
    ];

    settings = {
      # theme = "gruvbox_dark_hard";
      theme = "gruvbox_light_soft";
      editor = {
        bufferline = "multiple";
        idle-timeout = 5;
        copilot-auto-render = true;
        # undercurl = true;
        # true-color = true;
        soft-wrap.enable = true;

        file-picker = {
          git-exclude = false;
          git-global = false;
          hidden = false;
        };

        lsp = {
          display-inlay-hints = true;
        };
        cursor-shape.insert = "bar";
        insert-final-newline = false;
      };

      keys = {
        normal = {
          esc = [ "collapse_selection" "keep_primary_selection" ];
          Z = { Z = [ ":write-quit" ]; };
          space = {
            F = "file_picker";
            f = "file_picker_in_current_directory";

            # To use various repls (bash/ipython3/duckdb/sqlite etc.)
            # with helix as editor
            # For ipython3
            # 1. Use `%autoindent` to disable autoindent
            # 2. `%logstart -o` to save code and output to a file.
            l = ''
              :pipe-to python3 -c "import shlex, os, sys;a=sys.stdin.read();a += '\\n'; os.system(shlex.join(['tmux', 'send-keys', '-t', '1', a]));"'';

            L = ":run-shell-command tmux send-keys -t 1 C-c";

            o = {
              l = ":open ~/.config/helix/languages.toml";
              c = ":config-open";
            };
            w = {
              x = ":quit-all";
              X = ":quit-all!";
            };

            t = {
              h = ":toggle-option lsp.display-inlay-hints";
              e = ":toggle-option lsp.inline-diagnostics.enabled";
              l = {

                # https://github.com/helix-editor/helix/pull/6417#issuecomment-1740819264
                n = ":set-option lsp.inline-diagnostics.other-lines []";
                e =
                  '':set-option lsp.inline-diagnostics.other-lines ["error"]'';
                w = ''
                  :set-option lsp.inline-diagnostics.other-lines ["warning","error"]'';
                i = ''
                  :set-option lsp.inline-diagnostics.other-lines ["info","warning","error"]'';
                h = ''
                  :set-option lsp.inline-diagnostics.other-lines ["hint","info","warning","error"]'';
                o = ":set-option lsp.inline-diagnostics.enabled false";
              };
            };

            m = comment_binding;

          };
        };

        insert = {
          "C-e" = "copilot_show_completion";
          "C-y" = "copilot_apply_completion";
          "C-space" = "completion";
        };

        select = {
          space = {
            l = ''
              :pipe-to python3 -c "import shlex, os, sys;a=sys.stdin.read();a += '\\n'; os.system(shlex.join(['tmux', 'send-keys', '-t', '1', a]));"'';

            m = comment_binding;
          };
        };
      };
    };

    languages = {
      # Servers
      language-server.pyright = {
        command = "pyright-langserver";
        args = [ "--stdio" ];
        config = {
          venv = "./.venv";
          venvPath = ".";
        };
      };
      language-server.gopls = {
        environment = { "GOFLAGS" = "-tags=cluster"; };
      };
      language-server.typst-lsp = {
        language-id = "typst";
        command = "typst-lsp";
      };

      # Language config
      language = [
        {
          name = "python";
          language-servers = [ "pyright" ];
        }

        {
          name = "c";
          language-servers = [ "clangd" ];
          formatter = {
            command = "clang-format";
            args = [ "--style=google" ];
          };
        }
        {
          name = "svelte";
          language-servers = [ "svelteserver" "tailwindcss-ls" ];
          block-comment-tokens = [{start="<!--"; end="-->";}];
        }
        {
          name = "css";
          language-servers =
            [ "tailwindcss-ls" "vscode-css-language-server" ];
        }
        {
          name = "html";
          language-servers =
            [ "tailwindcss-ls" "vscode-html-language-server" ];
        }
        {
          name = "caddyfile";
          roots = [ ];
          scope = "source.caddyfile";
          injection-regex = "caddyfile";
          file-types = [ "Caddyfile" ];
          comment-token = "#";
          language-servers = [ ];
          indent = {
            tab-width = 4;
            unit = "\\t";
          };
          formatter = { command = "caddy-fmt"; };
        }
        {
          name = "typst";
          roots = [ ];
          scope = "source.typst";
          injection-regex = "typst";
          file-types = [ "typ" ];
          comment-token = "//";
          indent = {
            tab-width = 4;
            unit = "	";
          };
          language-servers = [ "typst-lsp" ];
        }

        {
          name = "javascript";
          formatter = {
            command = "biome";
            args = [ "format" "--stdin-file-path=x.js" ];
          };
          language-servers = [ "typescript-language-server" ];
        }
        {
          name = "typescript";
          formatter = {
            command = "biome";
            args = [ "format" "--stdin-file-path=x.ts" ];
          };
          language-servers = [ "typescript-language-server" ];
        }
        {
          name = "nix";
          formatter = { command = "nixfmt"; };
        }
      ];

    };
  };
}
