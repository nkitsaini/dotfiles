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
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, home-manager, nkitsaini_helix, nur, disko, ... }@inputs:
    let
      mkSystem = hostname:
        nixpkgs.lib.nixosSystem {
          # NOTE: Change this to aarch64-linux if you are on ARM
          inherit system;
          specialArgs = {
            inherit inputs;
            inherit system;
            inherit hostname;
          };
          modules = [
            ./devices/${hostname}
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
          ];
        };

      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."asaini" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./devices/shifu/home.nix ];
        extraSpecialArgs = {
          inherit nkitsaini_helix;
          inherit system;
          inherit nur;
          enableNixGL = true;
        };
      };

      nixosConfigurations.monkey = mkSystem "monkey";
      nixosConfigurations.iso = mkSystem "iso";


      # TODO: disko config remaining
      nixosConfigurations.oogway = mkSystem "oogway";

      # TODO: following configs to be in similar fashion as `monkey`
      # i.e.
      # 1. use fixed users,
      # 2. rename configuration.nix -> default.nix
      # 3. have home-manager config imported through default.nix
      # 4. manage disk through disko
      # ... or something I missed
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
    };
}
