{ bun2nix, lib }:

bun2nix.mkDerivation {
  pname = "mantis-web";
  version = "0.1.0";
  packageJson = ./web/package.json;
  src = lib.fileset.toSource {
    root = ./web;
    fileset = lib.fileset.unions [
      ./web/package.json
      ./web/bun.lock
      ./web/bun.nix
      ./web/svelte.config.js
      ./web/tsconfig.json
      ./web/vite.config.ts
      ./web/src
    ];
  };
  bunDeps = bun2nix.fetchBunDeps { bunNix = ./web/bun.nix; };
  dontRunLifecycleScripts = true;
  buildPhase = ''
    runHook preBuild
    bun run check
    bun run build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    cp -r build "$out"
    runHook postInstall
  '';
}
