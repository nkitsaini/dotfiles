{
  description = "markdown-lsp: a high-quality, configurable Markdown language server written in Rust";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      # `nix develop` -> a shell with the Rust toolchain used to build/test this crate.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            rustc
            rustfmt
            clippy
            rust-analyzer
            # `copyAsInlined` shells out to a clipboard tool; have one in the dev shell too.
            wl-clipboard
            xclip
          ];

          # Let rust-analyzer find the standard library sources.
          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

          shellHook = ''
            echo "markdown-lsp dev shell — $(cargo --version)"
          '';
        };
      });

      # `nix build` -> the release binary, wrapped so a clipboard tool is always
      # on PATH for the "copy as inlined Markdown" command.
      packages = forAllSystems (pkgs:
        let
          # wl-clipboard/xclip are Linux-only; macOS has `pbcopy` built in.
          clipboardTools = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.wl-clipboard pkgs.xclip ];
        in
        {
          default = pkgs.rustPlatform.buildRustPackage {
            pname = "markdown-lsp";
            version = "0.1.0";
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;

            # Tests are exercised in CI / the dev shell; skip them here to keep the
            # package build fast and free of the criterion benches.
            doCheck = false;

            nativeBuildInputs = [ pkgs.makeWrapper ];
            postInstall = pkgs.lib.optionalString (clipboardTools != [ ]) ''
              wrapProgram $out/bin/markdown-lsp \
                --suffix PATH : ${pkgs.lib.makeBinPath clipboardTools}
            '';

            meta = {
              description = "A high-quality, configurable Markdown language server written in Rust";
              mainProgram = "markdown-lsp";
              license = with pkgs.lib.licenses; [ mit asl20 ];
            };
          };
        });
    };
}
