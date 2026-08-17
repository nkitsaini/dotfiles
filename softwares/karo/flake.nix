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

      checks = forAllSystems (pkgs: {
        fish-completion =
          let
            karo = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          in
          pkgs.runCommand "karo-fish-completion"
            {
              nativeBuildInputs = [
                pkgs.fish
                karo
              ];
            }
            ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME" fixture
              printf '%s\n' '{"scripts":{"build":"vite build","dev":"vite dev"}}' \
                > fixture/package.json
              cd fixture

              # Point fish at the installed artifact, exercising both packaging
              # and the completion definition through fish's public interface.
              export fish_complete_path="${karo}/share/fish/vendor_completions.d"

              tasks="$(karo --complete-tasks)"
              printf '%s\n' "$tasks" | grep -Fx $'build\tvite build'
              ! printf '%s\n' "$tasks" | grep -q 'bun:build'

              qualified="$(fish --no-config -c 'complete -C "karo bun:"')"
              test "$qualified" = $'bun:build\tvite build\nbun:dev\tvite dev'

              options="$(fish --no-config -c 'complete -C "karo --v"')"
              test "$options" = $'--version\tShow version'

              # Once the task has been selected, arguments belong to its runner;
              # karo must not fall back to completing files itself.
              test -z "$(fish --no-config -c 'complete -C "karo build "')"

              touch "$out"
            '';
      });
    };
}
