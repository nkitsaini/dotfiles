{
  description = "Home Manager configuration of ankit";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nkitsaini_helix = {
      url = "github:nkitsaini/helix/nkit-driver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/NUR";
  };

  outputs = { nixpkgs, home-manager, nkitsaini_helix, nur, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."ankit" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./devices/thinkpad_e14/home.nix ];
        extraSpecialArgs = {
          inherit nkitsaini_helix;
          inherit system;
          inherit nur;
          enableNixGL = true;
        };

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
      homeConfigurations."asaini" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./devices/thinkpad_p14s/home.nix ];
        extraSpecialArgs = {
          inherit nkitsaini_helix;
          inherit system;
          inherit nur;
          enableNixGL = true;
        };

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };

      # NOTE: 'nixos' is the default hostname set by the installer
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        # NOTE: Change this to aarch64-linux if you are on ARM
        inherit system;
        modules = [
          # idea_from: https://discourse.nixos.org/t/command-not-found-unable-to-open-database/3807/11
          # syntax_from: https://raw.githubusercontent.com/MatthewCroughan/nixcfg/master/flake.nix
          # { nixpkgs.overlays = [ nur.overlay ]; }
          # ({ pkgs, ... }:
          #   let
          #     nur-no-pkgs =
          #       import nur { nurpkgs = import nixpkgs { inherit system; }; };
          #   in {
          #     imports = [ nur-no-pkgs.repos.iopq.modules.xraya ];
          #     services.xraya.enable = true;
          #   })
          ./devices/thinkpad_e14_nix/nixos-config/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.ankits =
              import ./devices/thinkpad_e14_nix/home.nix;
            home-manager.extraSpecialArgs = {
              inherit system;
              inherit nkitsaini_helix;
              inherit nur;
              enableNixGL = false;
            };
          }
        ];
      };

    };
}
