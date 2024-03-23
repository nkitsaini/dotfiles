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

  outputs = { nixpkgs, home-manager, nkitsaini_helix, nur, ... }@inputs:
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
      nixosConfigurations.monkey = nixpkgs.lib.nixosSystem {
        # NOTE: Change this to aarch64-linux if you are on ARM
        inherit system;
        specialArgs = {
          inherit inputs;
          inherit system;
        };
        modules = [ ./devices/monkey home-manager.nixosModules.home-manager ];
      };

      nixosConfigurations.crane = nixpkgs.lib.nixosSystem {
        # NOTE: Change this to aarch64-linux if you are on ARM
        inherit system;
        modules = [
          ./devices/crane/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.root = import ./devices/crane/home.nix;
            home-manager.extraSpecialArgs = {
              inherit system;
              inherit nkitsaini_helix;
              enableNixGL = false;
            };
          }
        ];
      };

      nixosConfigurations.oogway = nixpkgs.lib.nixosSystem {
        # NOTE: Change this to aarch64-linux if you are on ARM
        inherit system;
        modules = [
          ./devices/oogway/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.oogway = import ./devices/oogway/home.nix;
            home-manager.extraSpecialArgs = {
              inherit system;
              inherit nur;
              inherit nkitsaini_helix;
              enableNixGL = false;
            };
          }
        ];
      };

      iso = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit system;
          inherit inputs;
        };
        modules =
          [ ./devices/iso/default.nix home-manager.nixosModules.home-manager ];
      };

    };
}
