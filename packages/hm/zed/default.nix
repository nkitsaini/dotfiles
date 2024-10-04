{
  pkgs,
  nixGLCommandPrefix ? "",
  ...
}:
{
  home.packages =
    with pkgs;
    [
      zed-editor

    ]
    ++ (
      if nixGLCommandPrefix != "" then
        [
          (writeShellApplication {
            name = "zed";
            text = ''
              exec nixgl-vulkan-run ${pkgs.zed-editor}/bin/zeditor "$@"
            '';
          })
        ]
      else
        [
          (writeShellApplication {
            name = "zed";
            text = ''
              exec ${pkgs.zed-editor}/bin/zeditor "$@"
            '';
          })
        ]
    );

}
