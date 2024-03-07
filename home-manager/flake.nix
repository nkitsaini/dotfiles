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

    # https://github.com/outfoxxed/hy3?tab=readme-ov-file#nix
    hyprland.url =
      "github:hyprwm/Hyprland?ref=v0.35.0"; # where {version} is the hyprland release version
    # or "github:hyprwm/Hyprland" to follow the development branch

    hy3 = {
      url =
        "github:outfoxxed/hy3?ref=hl0.35.0"; # where {version} is the hyprland release version
      # or "github:outfoxxed/hy3" to follow the development branch.
      # (you may encounter issues if you dont do the same for hyprland)
      inputs.hyprland.follows = "hyprland";
    };
  };

  outputs = { nixpkgs, home-manager, nkitsaini_helix, nur, hyprland, hy3, ... }:
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
          inherit hyprland;
          inherit hy3;
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
          inherit hyprland;
          inherit hy3;
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
              inherit hyprland;
              inherit hy3;
              inherit nkitsaini_helix;
              inherit nur;
              enableNixGL = false;
            };
          }
        ];
      };

      nixosConfigurations.skygod = nixpkgs.lib.nixosSystem {
        # NOTE: Change this to aarch64-linux if you are on ARM
        inherit system;
        modules = [
          ./devices/skygod/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.ankits =
              import ./devices/skygod/home.nix;
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
