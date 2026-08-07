{
  description = "Mantis: reliable Git synchronization for Termux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
    bun2nix.url = "github:nix-community/bun2nix?tag=2.0.1";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
  };

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };

  outputs = inputs:
    let
      eachSystem = inputs.nixpkgs.lib.genAttrs (import inputs.systems);
      pkgsFor = eachSystem (system: import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.bun2nix.overlays.default ];
      });
    in {
      packages = eachSystem (system:
        let
          pkgs = pkgsFor.${system};
          frontend = pkgs.callPackage ./frontend.nix { };
          androidPkgs = import inputs.nixpkgs {
            localSystem = system;
            crossSystem = inputs.nixpkgs.lib.systems.examples.aarch64-android-prebuilt // {
              # Keep the binary compatible with Android 7 / Termux API 24+
              # instead of inheriting Nixpkgs' current API-35 example default.
              androidSdkVersion = "24";
            };
            # Android's NDK closure is marked unfree in Nixpkgs. This setting is
            # scoped to the cross package set and does not affect host packages.
            config.allowUnfree = true;
          };
        in {
          default = pkgs.callPackage ./package.nix { inherit frontend; };
          inherit frontend;
          android-aarch64 = androidPkgs.callPackage ./package.nix { inherit frontend; };
        });

      checks = eachSystem (system: {
        inherit (inputs.self.packages.${system}) default frontend android-aarch64;
      });

      devShells = eachSystem (system:
        let pkgs = pkgsFor.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ bun bun2nix cargo rustc rustfmt clippy rust-analyzer git sqlite ];
            shellHook = ''export RUST_BACKTRACE=1'';
          };
        });
    };
}
