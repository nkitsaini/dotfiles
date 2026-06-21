{ pkgs, ... }:
let
  camera-ctl = pkgs.writeShellApplication {
    name = "camera-ctl";
    runtimeInputs = [
      pkgs.v4l-utils          # provides v4l2-ctl
      (pkgs.python3.withPackages (_: [ ]))
    ];
    text = ''
      exec python3 ${./camera-ctl.py} "$@"
    '';
  };
in
{
  home.packages = [ camera-ctl ];
}
