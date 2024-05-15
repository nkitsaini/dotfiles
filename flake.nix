{
  description = "Home Manager configuration of ankit";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nkitsaini_helix = {
      url = "github:nkitsaini/helix/nkit-driver-backup-2024-04-28";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    # nkitsaini_notes_utils = {
    #   # url = "git+ssh://git@github.com/nkitsaini/hive.git?ref=main&dir=notes_utils";
    #   url = "git+file:///home/kit/code/hive?dir=notes_utils";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    nur = { url = "github:nix-community/NUR"; };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
      pkgs = import nixpkgs {
        system = system;
        overlays = [ inputs.nixgl.overlay ];
      };

    in {
      # ===== Home-manager only configs
      homeConfigurations."shifu" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./devices/shifu/home.nix ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
          nixGLCommandPrefix = "${pkgs.nixgl.nixGLMesa}/bin/nixGLMesa ";
        };
      };

      # ===== Nixos configs
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
              nixGLCommandPrefix = "";
            };
          }
        ];
      };
    };
}
