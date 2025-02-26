{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = _: {
    nixosModule = {
      a = 3;
    };
  };
}
