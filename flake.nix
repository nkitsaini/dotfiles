rec {
  description = "Home Manager configuration of ankit";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    kit = {
      url = "path:modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim"; # This is one that works with current nixpkgs lock. Will need to update this when nixpkgs is updated.
      # I just searched git log of nixvim for commit hash of current nixpkgs
      # If using a stable channel you can use `url = "github:nix-community/nixvim/nixos-<version>"`
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # doom-emacs is a configuration framework for GNU Emacs.
    doomemacs = {
      url = "github:doomemacs/doomemacs";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    volume_control_rs = {
      url = "path:softwares/volume_control";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      home-manager,
      nixvim,

      nur,
      disko,
      ...
    }@inputs:
    let
      mkSystem =
        {
          hostname,
          extraModules ? [ ],
          autoIncludeDeviceModule ? true,
          username ? "kit",
        }:
        nixpkgs.lib.nixosSystem {
          # NOTE: Change this to aarch64-linux if you are on ARM
          inherit system;
          specialArgs = {
            inherit inputs;
            inherit system;
            inherit hostname;
            inherit username;
          };
          modules = [
            home-manager.nixosModules.home-manager
            inputs.nur.modules.nixos.default
            disko.nixosModules.disko
            inputs.kit.nixosModules.default
            (
              { inputs, ... }:
              {
                nix.settings = {
                  substituters = nixConfig.extra-substituters;
                  trusted-public-keys = nixConfig.extra-trusted-public-keys;
                };

                home-manager.sharedModules = [
                  inputs.kit.hm.default
                ];

              }
            )
          ]
          ++ extraModules
          ++ (if (autoIncludeDeviceModule) then [ ./devices/${hostname} ] else [ ]);

        };

      system = "x86_64-linux";
      pkgs = import nixpkgs {
        system = system;
        overlays = [
          inputs.nur.overlay
          inputs.nixgl.overlay
        ];
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          git-crypt
        ];
      };
      # ===== Home-manager only configs
      homeConfigurations."shifu" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./devices/shifu/home.nix
          inputs.kit.hm.default
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;

          # wezterm didn't work with only vulkan, zed didn't work with only GL.
          # But can't include vulkan as it can break non-gui packages due to llvm lib in `LD_LIBRARY_PATH`. So open-gl globally, and vulkan for specific packages after: https://github.com/nix-community/home-manager/pull/5355, right now it is manual: `nixgl-vulkan-run ....`
          nixGLCommandPrefix = "${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel  ";
          disableSwayLock = true;
        };
      };
      homeConfigurations."shifu_remote" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./devices/shifu_remote/home.nix
          inputs.kit.hm.default
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
        };
      };

      # ===== Nixos configs
      nixosConfigurations.monkey = mkSystem {
        hostname = "monkey";
        extraModules = [ nixos-hardware.nixosModules.lenovo-thinkpad-e14-amd ];
      };
      nixosConfigurations.iso = mkSystem { hostname = "iso"; };

      nixosConfigurations.deepak = mkSystem {
        hostname = "deepak";
        username = "deepak";
      };
      nixosConfigurations.akanksha = mkSystem {
        hostname = "akanksha";
        username = "akanksha";
      };

      # TODO: disko config remaining
      nixosConfigurations.oogway = mkSystem { hostname = "oogway"; };

      # TODO: following configs to be in similar fashion as `monkey`
      # i.e.
      # 1. use fixed users,
      # 2. rename configuration.nix -> default.nix
      # 3. have home-manager config imported through default.nix
      # 4. manage disk through disko
      # ... or something I missed
      nixosConfigurations.crane = mkSystem { hostname = "crane"; };
      nixosConfigurations.crane2 = mkSystem {
        hostname = "crane";
        autoIncludeDeviceModule = false;
        extraModules = [ ./devices/crane2 ];
      };
    };
  nixConfig = {
    extra-substituters = [ "https://helix.cachix.org" ];
    extra-trusted-public-keys = [ "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs=" ];
  };
}
