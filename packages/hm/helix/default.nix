{
  config,
  pkgs,
  inputs,
  system,
  ...
}:
{
  # TODO: use config.home-files to reference files inside current home-manager generation instead of path from home-directory. Currently config.home-files gives infinite recursion.
  home.sessionVariables = {
    EDITOR = "${config.home.homeDirectory}/.local/state/nix/profiles/home-manager/home-path/bin/hx";
  };
  programs.helix =
    let
      comment_binding = '':pipe ${pkgs.python312}/bin/python3 ${./commenter.py} --start-token="/*" --end-token="*/"'';
      markdown_table_formatter_stdin = pkgs.writeShellApplication {
        name = "markdown-table-formatter-stdin";
        runtimeInputs = [
          pkgs.bun
          pkgs.coreutils
        ];
        text = ''
          TEMPFILE=$(mktemp --suffix .markdown-table-formatter.md)
          cp /dev/stdin "$TEMPFILE"
          bunx markdown-table-formatter -- "$TEMPFILE" > /dev/null
          cat "$TEMPFILE"
          rm "$TEMPFILE"
        '';
      };
    in
    {
      enable = true;
      package = inputs.helix_master.packages.${system}.default;
      # defaultEditor = true; # does not provide absolute path so fails with sudo, but actually should it?, explicitly setting EDITOR for now

      extraPackages = with pkgs; [
        marksman
        markdown-oxide
        nil
        texlab
        gopls
        # golangci-lint-langserver
        rust-analyzer
        tinymist
        biome
        pyright
        dockerfile-language-server-nodejs
        docker-compose-language-service
        yaml-language-server
        ruff
        # nodePackages.vscode-css-languageserver-bin
        # nodePackages.vscode-json-languageserver-bin
        # nodePackages.vscode-html-languageserver-bin
        vscode-langservers-extracted
        # nodePackages.vscode-eslint-language-server
        nodePackages.typescript-language-server
        # nodePackages.graphql-language-service-cli
        svelte-language-server
        tailwindcss-language-server
        ltex-ls
      ];

      settings = {
        # theme = "amberwood";
        theme = "gruvbox_light_soft";
        editor = {
          bufferline = "multiple";
          idle-timeout = 5;
          completion-timeout = 5;
          auto-save.after-delay = {
            enable = true;
            timeout = 300;
          };
          # copilot-auto-render = true;
          # undercurl = true;
          # true-color = true;
          soft-wrap.enable = true;
          end-of-line-diagnostics = "hint";
          inline-diagnostics = {
            cursor-line = "info";
            other-lines = "disable";
          };

          file-picker = {
            git-exclude = false;
            git-global = false;
            hidden = false;
          };

          lsp = {
            display-inlay-hints = false;
          };
          cursor-shape.insert = "bar";
          insert-final-newline = false;
        };

        keys = {
          normal = {
            esc = [
              "collapse_selection"
              "keep_primary_selection"
            ];
            Z = {
              Z = [ ":write-quit" ];
            };
            X = "extend_line_up";
            space = {
              F = "file_picker";
              f = "file_picker_in_current_directory";

              # To use various repls (bash/ipython3/duckdb/sqlite etc.)
              # with helix as editor
              # For ipython3
              # 1. Use `%autoindent` to disable autoindent
              # 2. `%logstart -o` to save code and output to a file.
              l = '':pipe-to python3 -c "import shlex, os, sys;a=sys.stdin.read();a += '\\n'; os.system(shlex.join(['tmux', 'send-keys', '-t', '1', a]));"'';

              L = ":run-shell-command tmux send-keys -t 1 C-c";
              # n = [ "select_all" ":pipe notes-util 2>/dev/null" "goto_file_start" ];

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
              };

              # e = {
              #   "f"=":eslint-fix-all";
              # };

              m = {
                f = comment_binding;
                t = ":lsp-workspace-command today";
              };
            };
          };

          insert = {
            # "C-e" = "copilot_show_completion";
            # "C-y" = "copilot_apply_completion";
            # "C-space" = "completion"; # C-. is already bind
          };

          select = {
            space = {
              l = '':pipe-to python3 -c "import shlex, os, sys;a=sys.stdin.read();a += '\\n'; os.system(shlex.join(['tmux', 'send-keys', '-t', '1', a]));"'';

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
              showDocumentation = {
                enable = true;
              };
            };
            codeActionOnSave = {
              mode = "all";
            };
            experimental = { };
            problems = {
              shortenToSingleLine = false;
            };
            workingDirectory = {
              mode = "auto";
            };
          };
        };
        language-server.gopls = {
          environment = {
            "GOFLAGS" = "-tags=cluster";
          };
        };
        language-server.typst-lsp = {
          language-id = "typst";
          command = "tinymist";
        };
        language-server.ltex-lsp = {
          command = "${pkgs.ltex-ls}/bin/ltex-ls";
        };

        # Language config
        language = [
          {
            name = "text";
            scope = "source.txt";
            file-types = [ "txt" ];
            language-servers = [ "ltex-lsp" ];
          }
          {
            name = "markdown";
            language-servers = [
              "markdown-oxide"
              "ltex-lsp"
            ];
            formatter = {
              command = "${markdown_table_formatter_stdin}/bin/markdown-table-formatter-stdin";
              args = [ ];
            };
          }
          {
            name = "python";
            language-servers = [ "pyright" ];
            formatter = {
              command = "ruff";
              args = [
                "format"
                "--stdin-filename=x.py"
              ];
            };
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
            language-servers = [
              "svelteserver"
              "tailwindcss-ls"
              "vscode-eslint-language-server"
            ];
            block-comment-tokens = [
              {
                start = "<!--";
                end = "-->";
              }
            ];
          }
          {
            name = "jsx";
            language-servers = [
              "typescript-language-server"
              "tailwindcss-ls"
              "vscode-eslint-language-server"
            ];
          }
          {
            name = "tsx";
            language-servers = [
              "typescript-language-server"
              "tailwindcss-ls"
              "vscode-eslint-language-server"
            ];
          }
          {
            name = "css";
            language-servers = [
              "vscode-css-language-server"
              "tailwindcss-ls"
              "vscode-eslint-language-server"
            ];
          }
          {
            name = "html";
            language-servers = [
              "vscode-html-language-server"
              "tailwindcss-ls"
              "vscode-eslint-language-server"
            ];
          }
          {
            name = "yaml";
            indent = {
              tab-width = 2;
              unit = "  ";
            };
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
            formatter = {
              command = "caddy-fmt";
            };
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
            formatter = {
              command = "${pkgs.typstyle}/bin/typstyle";
              args = [ ];
            };
          }

          {
            name = "javascript";
            formatter = {
              command = "biome";
              args = [
                "format"
                "--stdin-file-path=x.js"
              ];
            };
            language-servers = [
              "typescript-language-server"
              "vscode-eslint-language-server"
            ];
          }
          {
            name = "typescript";
            formatter = {
              command = "biome";
              args = [
                "format"
                "--stdin-file-path=x.ts"
              ];
            };
            language-servers = [
              "typescript-language-server"
              "vscode-eslint-language-server"
            ];
          }
          {
            name = "nix";
            formatter = {
              command = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
            };
          }
        ];
      };
    };
}
