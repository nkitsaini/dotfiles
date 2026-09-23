{ pkgs }:
pkgs.code-cursor.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    ${pkgs.python3}/bin/python3 ${./patch-cursor-team-default.py} "$out/lib/cursor/resources/app"
    ${pkgs.nodejs}/bin/node ${./test-cursor-team-default.mjs} "$out/lib/cursor/resources/app"
  '';
})
