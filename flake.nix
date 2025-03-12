rec {
  description = "Home Manager configuration of ankit";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs_working_openwebui.url = "github:nixos/nixpkgs/4633a7c72337ea8fd23a4f2ba3972865e3ec685d";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    kit.url = "path:modules";
    kit.inputs.nixpkgs.follows = "nixpkgs";

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

    helix_master = {
      url = "github:helix-editor/helix";
      # NOTE: do not follow inputs, otherwise the cache will be of no use and
      #   the sun will go out of fashion before nix-build switch finishes.
      #   I know it'll be more network/space usage, but time is of essense.
      # inputs.nixpkgs.follows = "nixpkgs";
      # inputs.flake-utils.follows = "flake-utils";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TODO: This has been fixed in https://github.com/NixOS/nix/pull/10089
    # Bring relevant code in this repo itself
    # 
    # Nix doesn't have good support for importing flakes within same repo.
    # if imported using path:... syntax, it uses narHash which might be missing
    # from other developers machine.
    # The way of merging inputs together and calling `outputs` directly works *until* inputs have duplicates
    # So using seperate repo for this stuff. Ideally `dotfiles` repo can be used where you first push than nix flake update, but that seems confusing.
    # To update use `nix flake lock --update-input volume_control_rs`
    volume_control_rs = {
      url = "github:nkitsaini/hive?dir=volume_control";
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

      nixpkgs_working_openwebui,
      nur,
      disko,
      ...
    }@inputs:
    let
      mkSystem =
        {
          hostname,
          extraModules ? [ ],
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
            inherit pkgs_working_openwebui;
          };
          modules = [
            ./devices/${hostname}
            home-manager.nixosModules.home-manager
            inputs.nur.modules.nixos.default
            disko.nixosModules.disko
            (
              { inputs, ... }:
              {
                nix.settings = {
                  substituters = nixConfig.extra-substituters;
                  trusted-public-keys = nixConfig.extra-trusted-public-keys;
                };
              }
            )
          ] ++ extraModules;
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

      pkgs_working_openwebui = import nixpkgs_working_openwebui {
        system = system;
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
        modules = [ ./devices/shifu/home.nix ];
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
        modules = [ ./devices/shifu_remote/home.nix ];
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
    };
  nixConfig = {
    extra-substituters = [ "https://helix.cachix.org" ];
    extra-trusted-public-keys = [ "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs=" ];
  };
}
