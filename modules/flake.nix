{
  # NOTE: Run `nix flake update kit` at root for any changes in `input` to take effect.
  # I wasted a lot of time on this!!!
  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    git_syncer = {
      url = "path:../softwares/git_syncer";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { ... }@inputs:
    {
      nixosModules = {
        default = import ./nixos;
      };

      hm = {
        # default = import ./hm;
        default =
          {
            config,
            pkgs,
            lib,
            ...
          }:
          {
            _module.args.module_inputs = inputs;
            # _module.args.nixpkgs = nixpkgs;
            # _module.args.git_syncer = git_syncer;
            imports = [
              ./hm
            ];
          };
      };
    };
}
