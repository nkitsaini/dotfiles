{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.kit.rebuild;
  mutableCfg = config.kit.mutableConfig;

  json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;

  mutableConfigBin = pkgs.writeShellApplication {
    name = "kit-mutable-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.jq
      json5
    ];
    text = ''
      export KIT_MUTABLE_CONFIG_MANIFEST=${lib.escapeShellArg mutableCfg.manifest}
      ${builtins.readFile ./mutable-config.sh}
    '';
  };

  flakeRef = "${cfg.flake}#${cfg.attribute}";

  rebuildPrint =
    if cfg.kind == "home-manager" then
      "home-manager switch --flake ${flakeRef}"
    else
      "sudo nixos-rebuild switch --flake ${flakeRef}";

  rebuildBin =
    if cfg.enable then
      pkgs.writeShellScriptBin "kit-rebuild-impl" (
        if cfg.kind == "home-manager" then
          ''
            exec home-manager switch --flake ${lib.escapeShellArg flakeRef} "$@"
          ''
        else
          ''
            exec sudo nixos-rebuild switch --flake ${lib.escapeShellArg flakeRef} "$@"
          ''
      )
    else
      null;

  kit = pkgs.writeShellApplication {
    name = "kit";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export KIT_MUTABLE_CONFIG_BIN=${lib.escapeShellArg (lib.getExe mutableConfigBin)}
      ${lib.optionalString cfg.enable ''
        export KIT_REBUILD_BIN=${lib.escapeShellArg (lib.getExe rebuildBin)}
        export KIT_REBUILD_PRINT=${lib.escapeShellArg rebuildPrint}
      ''}
      ${builtins.readFile ./kit.sh}
    '';
  };
in
{
  imports = [ ./mutable-config.nix ];

  options.kit.rebuild = {
    enable = lib.mkEnableOption "kit rebuild helper for this profile";

    kind = lib.mkOption {
      type = lib.types.enum [
        "home-manager"
        "nixos"
      ];
      # Only consulted when enable = true; default avoids forcing every
      # profile to set it.
      default = "home-manager";
      description = "Which switch tool this machine uses.";
    };

    flake = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code/dotfiles";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/code/dotfiles"'';
      description = "Path to the dotfiles flake.";
    };

    attribute = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Flake attribute for this machine (for example `shifu` or `monkey`).";
    };
  };

  config = {
    assertions = [
      {
        assertion = (!cfg.enable) || (cfg.attribute != "");
        message = "kit.rebuild.attribute must be set when kit.rebuild.enable = true";
      }
    ];

    home.packages = [
      kit
      # Keep the mutable-config helper on PATH so activation and `kit config`
      # share one closure; users should prefer `kit config ...`.
      mutableConfigBin
    ];

    xdg.configFile."fish/completions/kit.fish".source = ./completions.fish;

    # Backwards-compatible name used across device configs.
    programs.fish.shellAliases = lib.mkIf cfg.enable {
      rebuild-system = "kit rebuild";
    };

    # Detect drift before Home Manager's write boundary, so an ordinary
    # conflict aborts before this activation mutates the home directory.
    home.activation.kitMutableConfigCheck = lib.mkIf (mutableCfg.files != { }) (
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        run ${lib.getExe kit} config __check
      ''
    );

    home.activation.kitMutableConfig = lib.mkIf (mutableCfg.files != { }) (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${lib.getExe kit} config __apply
      ''
    );
  };
}
