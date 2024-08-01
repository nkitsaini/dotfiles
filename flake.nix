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
    nur = {url = "github:nix-community/NUR";};
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TODO: these belong in dotfiles repo itself.
    # But nix doesn't have good support for importing flakes within same repo.
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

  outputs = {
    self,
    nixpkgs,
    nixos-hardware,
    home-manager,
    nur,
    disko,
    ...
  } @ inputs: let
    mkSystem = {
      hostname,
      extraModules ? [],
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
        modules =
          [
            ./devices/${hostname}
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            ({inputs, ...}: {
              nix.settings = {
                substituters = inputs.self.nixConfig.extra-substituters;
                trusted-public-keys = inputs.self.nixConfig.extra-trusted-public-keys;
              };
            })
          ]
          ++ extraModules;
      };

    system = "x86_64-linux";
    pkgs = import nixpkgs {
      system = system;
      overlays = [inputs.nixgl.overlay];
    };
  in {
    # ===== Home-manager only configs
    homeConfigurations."shifu" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      # Specify your home configuration modules here, for example,
      # the path to your home.nix.
      modules = [./devices/shifu/home.nix];
      extraSpecialArgs = {
        inherit inputs;
        inherit system;
        nixGLCommandPrefix = "${pkgs.nixgl.nixGLMesa}/bin/nixGLMesa ";
        disableSwayLock = true;
      };
    };

    # ===== Nixos configs
    nixosConfigurations.monkey = mkSystem {
      hostname = "monkey";
      extraModules = [nixos-hardware.nixosModules.lenovo-thinkpad-e14-amd];
    };
    nixosConfigurations.iso = mkSystem {hostname = "iso";};

    nixosConfigurations.deepak = mkSystem {
      hostname = "deepak";
      username = "deepak";
    };
    nixosConfigurations.akanksha = mkSystem {
      hostname = "akanksha";
      username = "akanksha";
    };

    # TODO: disko config remaining
    nixosConfigurations.oogway = mkSystem {hostname = "oogway";};

    # TODO: following configs to be in similar fashion as `monkey`
    # i.e.
    # 1. use fixed users,
    # 2. rename configuration.nix -> default.nix
    # 3. have home-manager config imported through default.nix
    # 4. manage disk through disko
    # ... or something I missed
    nixosConfigurations.crane = mkSystem {hostname = "crane";};
  };
  nixConfig = {
    extra-substituters = ["https://helix.cachix.org"];
    extra-trusted-public-keys = ["helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="];
  };
}
