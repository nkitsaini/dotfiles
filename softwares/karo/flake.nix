{
  description = "karo: one front-end for every task runner (just, bun/npm/pnpm/yarn, deno, go-task, make, uv)";

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
          nativeBuildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
          ];

          shellHook = ''
            export RUST_BACKTRACE=1
          '';
        };
      });

      # `nix build` -> the release binary
      packages = forAllSystems (pkgs: {
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "karo";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = [ pkgs.installShellFiles ];

          # Placed in share/{fish/vendor_completions.d,bash-completion/completions,
          # zsh/site-functions}, which the nixpkgs shells pick up from profiles.
          postInstall = ''
            installShellCompletion --cmd karo \
              --fish completions/karo.fish \
              --bash completions/karo.bash \
              --zsh completions/_karo
          '';

          meta = {
            description = "One front-end for every task runner";
            mainProgram = "karo";
            license = with pkgs.lib.licenses; [ mit ];
          };
        };
      });
    };
}
