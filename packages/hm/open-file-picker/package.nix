{
  fd,
  glib,
  lib,
  python3,
  rustPlatform,
  util-linux,
  writeTextFile,
}:
let
  render =
    replacements: path:
    builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
      builtins.readFile path
    );
  search = writeTextFile {
    name = "open-file-search";
    destination = "/bin/open-file-search";
    executable = true;
    text = ''
      #!${lib.getExe python3}
      ${render { "@FD@" = "${lib.getExe fd}"; } ./search.py}
    '';
  };
in
rustPlatform.buildRustPackage {
  pname = "open-file-picker";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type: type != "directory" || baseNameOf path != "target";
  };
  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    substituteInPlace src/main.rs \
      --replace-fail '@GIO@' '${glib}/bin/gio' \
      --replace-fail '@SEARCH@' '${lib.getExe search}' \
      --replace-fail '@SETSID@' '${util-linux}/bin/setsid'
  '';

  meta.mainProgram = "open-file-picker";
}
