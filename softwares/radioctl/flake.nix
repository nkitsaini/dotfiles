{
  description = "radioctl: a high-quality, user-friendly, and robust TUI replacement for bluetoothctl and nmtui";

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
            pkg-config
            cargo
            rustc
            rust-analyzer
          ];

          buildInputs = with pkgs; [
            dbus
            udev
          ];

          shellHook = ''
            export RUST_BACKTRACE=1
          '';
        };
      });

      # `nix build` -> the release binary
      packages = forAllSystems (pkgs: {
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "radioctl";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          doCheck = false;

          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.dbus pkgs.udev ];

          meta = {
            description = "A high-quality TUI replacement for bluetoothctl and nmtui";
            mainProgram = "radioctl";
            license = with pkgs.lib.licenses; [ mit ];
          };
        };
      });
    };
}
