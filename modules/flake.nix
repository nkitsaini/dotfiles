{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = _: {
    nixosModules = {
      default = import ./nixos;
    };

    hm = {
      default = import ./hm;
    };
  };
}
