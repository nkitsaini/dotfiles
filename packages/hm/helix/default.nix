{ config, pkgs, inputs, system, ... }: {
  # TODO: use config.home-files to reference files inside current home-manager generation instead of path from home-directory. Currently config.home-files gives infinite recursion.
  home.sessionVariables = {
    EDITOR = "${config.home.homeDirectory}/.local/state/nix/profiles/home-manager/home-path/bin/hx";
  };
  programs.helix = let
    comment_binding = ''
      :pipe ${pkgs.python312}/bin/python3 ${config.home.homeDirectory}/code/hive/commenter/commenter.py --start-token="/*" --end-token="*/"'';
    nodeDependencies = (pkgs.callPackage ./svelte_langauge_server/default.nix {
      inherit pkgs system;
    });
  in {
    enable = true;
    package = inputs.nkitsaini_helix.packages.${system}.default;
    # defaultEditor = true; # does not provide absolute path so fails with sudo, but actually should it?, explicitly setting EDITOR for now

    extraPackages = with pkgs; [
      marksman
      nil
      texlab
      gopls
      golangci-lint-langserver
      rust-analyzer
      typst-lsp
      biome
      nodePackages.pyright
      dockerfile-language-server-nodejs
      # nodePackages.vscode-css-languageserver-bin
      # nodePackages.vscode-json-languageserver-bin
      # nodePackages.vscode-html-languageserver-bin
      vscode-langservers-extracted
      # nodePackages.vscode-eslint-language-server
      nodePackages.typescript-language-server
      nodePackages.graphql-language-service-cli
      # nodePackages.svelte-language-server # use this instead of custom once nixos-unstable has 0.16.8 or newer (required for svelte 5)
      nodeDependencies.svelte-language-server
      tailwindcss-language-server
    ];

    settings = {
      # theme = "gruvbox_dark_hard";
      theme = "gruvbox_light_soft";
      editor = {
        bufferline = "multiple";
        idle-timeout = 5;
        completion-timeout = 5;
        copilot-auto-render = true;
        # undercurl = true;
        # true-color = true;
        soft-wrap.enable = true;

        file-picker = {
          git-exclude = false;
          git-global = false;
          hidden = false;
        };

        lsp = { display-inlay-hints = true; };
        cursor-shape.insert = "bar";
        insert-final-newline = false;
      };

      keys = {
        normal = {
          esc = [ "collapse_selection" "keep_primary_selection" ];
          Z = { Z = [ ":write-quit" ]; };
          X = "extend_line_up";
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

            e = {
              "f"=":eslint-fix-all";
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
      language-server.vscode-eslint-language-server = {
        command = "vscode-eslint-language-server";
        args = [ "--stdio" ];
        config = {
          provideFormatter = true;
          nodePath = "";
          onIgnoredFiles = "off";
          quiet = false;
          rulesCustomizations = [ ];
          run = "onType";
          validate = "on";
          codeAction = {
            disableRuleComment = {
              enable = true;
              location = "separateLine";
            };
            showDocumentation = { enable = true; };
          };
          codeActionOnSave = { mode = "all"; };
          experimental = { };
          problems = { shortenToSingleLine = false; };
          workingDirectory = { mode = "auto"; };

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
          language-servers =
            [ "svelteserver" "tailwindcss-ls" "vscode-eslint-language-server" ];
          block-comment-tokens = [{
            start = "<!--";
            end = "-->";
          }];
        }
        {
          name = "jsx";
          language-servers = [
            "tailwindcss-ls"
            "typescript-language-server"
            "vscode-eslint-language-server"
          ];
        }
        {
          name = "tsx";
          language-servers = [
            "tailwindcss-ls"
            "typescript-language-server"
            "vscode-eslint-language-server"
          ];
        }
        {
          name = "css";
          language-servers = [
            "tailwindcss-ls"
            "vscode-css-language-server"
            "vscode-eslint-language-server"
          ];
        }
        {
          name = "html";
          language-servers = [
            "tailwindcss-ls"
            "vscode-html-language-server"
            "vscode-eslint-language-server"
          ];
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
          language-servers =
            [ "typescript-language-server" "vscode-eslint-language-server" ];
        }
        {
          name = "typescript";
          formatter = {
            command = "biome";
            args = [ "format" "--stdin-file-path=x.ts" ];
          };
          language-servers =
            [ "typescript-language-server" "vscode-eslint-language-server" ];
        }
        {
          name = "nix";
          formatter = { command = "${pkgs.alejandra}/bin/alejandra"; };
        }
      ];

    };
  };
}
