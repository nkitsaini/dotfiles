{
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
        default = import ./hm;
      };
    };
}
