{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.kit.firefox;

  # Firefox with a patched browser/omni.ja. Two patches:
  #
  # 1. Default container (see ./kit_containers.sys.mjs): native "new tab"
  #    (Ctrl+T, + button, File > New Tab) and external link opens create the
  #    tab directly in the container named by the `kit.containers.default`
  #    pref (set per host via `kit.firefox.defaultContainer` below). Doing
  #    this in the native handlers instead of an extension means it works
  #    regardless of keyboard focus and there is no runtime component that
  #    can fail open: if the pref is unset behavior is stock, and if a
  #    Firefox update moves the patched code, `--replace-fail` aborts the
  #    *build* instead of silently regressing.
  #
  # 2. Strip `reserved="true"` from chrome keybindings so extensions
  #    (Tridactyl) may override keys like Ctrl+T. Predates patch 1 and is no
  #    longer needed for the container feature; kept so existing Tridactyl
  #    binds keep working.
  firefox_patched = pkgs.firefox.overrideAttrs (oldAttrs: {
    buildInputs = oldAttrs.buildInputs ++ [
      pkgs.perl
      pkgs.unzip
      pkgs.zip
    ];
    buildCommand =
      oldAttrs.buildCommand
      + ''
        omni="$out/lib/firefox/browser/omni.ja"
        unpack=$(mktemp -d)
        # unzip exits 1/2 on omni.ja's nonstandard-but-harmless zip layout
        ${pkgs.unzip}/bin/unzip -q "$omni" -d "$unpack" || test $? -le 2

        cp ${./kit_containers.sys.mjs} "$unpack/modules/KitContainers.sys.mjs"

        # The try/catch IIFE guarantees a broken/missing helper degrades to
        # stock behavior (uncontained tab, visibly badge-less) instead of
        # breaking new-tab creation altogether.
        kitResolve() {
          echo "(() => { try { return ChromeUtils.importESModule(\"resource:///modules/KitContainers.sys.mjs\").KitContainers.defaultUserContextId($1); } catch (e) { return 0; } })()"
        }

        # New tabs (BrowserCommands.openTab): open in the default container.
        substituteInPlace "$unpack/chrome/browser/content/browser/browser-commands.js" \
          --replace-fail \
          'resolveOnNewTabCreated: resolve,' \
          "resolveOnNewTabCreated: resolve, userContextId: $(kitResolve window),"

        # External opens: fall back to the default container when Firefox's
        # native container guessing (most open tabs with the same host) finds
        # nothing. guessUserContextIdEnabled = isExternal && !force-default
        # pref, so both escape hatches stay honored.
        substituteInPlace "$unpack/modules/BrowserDOMWindow.sys.mjs" \
          --replace-fail \
          'lazy.URILoadingHelper.guessUserContextId(aURI)) ||' \
          "lazy.URILoadingHelper.guessUserContextId(aURI)) || (guessUserContextIdEnabled && $(kitResolve null)) ||"

        grep -rlZF 'reserved="true"' "$unpack" | xargs -0 -r perl -i -pne 's/reserved="true"/               /g'

        rm "$omni"
        (cd "$unpack" && ${pkgs.zip}/bin/zip -qr9XD "$omni" -- *)
        rm -rf "$unpack"
      '';
  });
in
{
  options.kit.firefox.defaultContainer = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "work";
    description = ''
      Name of the Firefox container that new tabs (Ctrl+T, + button) and
      external links open in by default on this machine. Matched against
      container names: exact first, then case-insensitive if unambiguous.
      null keeps stock Firefox behavior.
    '';
  };

  config = {
    programs.firefox.enable = true;
    programs.firefox.configPath = ".mozilla/firefox";

    home.packages = with pkgs; [
      xdg-desktop-portal-xapp
      xdg-desktop-portal-gtk
    ];

    programs.firefox.package = firefox_patched.override {
      # See nixpkgs' firefox/wrapper.nix to check which options you can use
      nativeMessagingHosts = [
        # Tridactyl native connector
        pkgs.tridactyl-native
      ];
    };

    # TODO: use absolute path to `hx`. It's not in helix_master/bin/hx but in
    # home-manager-path/bin/hx
    xdg.configFile."tridactyl/tridactylrc".text =
      let
        kitAutocmds = [
          # TODO: `.*.*` as tridactyl uses the regex as key, so it needs to be unique and not conflict with ./location.js rule
          "TriStart .*.* js -s -r ./autoclose.js"
          "DocStart .*.* js -s -r ./autoclose.js"
          "TriStart (www\\.)?youtube.com js -s -r ./grayscale.js"
          "DocStart (www\\.)?youtube.com js -s -r ./grayscale.js"
          "DocStart .* js -s -r ./location.js"
        ];
        mkAutocmd = cmd: "autocmd ${cmd}";
        mkAutocmdDelete = cmd: "autocmddelete ${cmd}";
        kitSetup = pkgs.lib.concatMapStringsSep " | " mkAutocmd kitAutocmds;
        kitStop = pkgs.lib.concatMapStringsSep " | " mkAutocmdDelete kitAutocmds;
      in
      ''
        js tri.config.set("editorcmd", "${pkgs.ghostty}/bin/ghostty -e hx")
        js tri.config.set("theme", "shydactyl")
        bind --mode=normal <C-V> mode ignore
        unbind --mode=normal <C-f>

        # New tabs open in a per-host default container natively (patched
        # omni.ja reading the kit.containers.default pref); no Tridactyl bind
        # needed. See kit.firefox.defaultContainer in the firefox hm module.
        #
        # To view current autocmd's run `:viewconfig autocmd`

        command kit_status viewconfig autocmds
        command kit_setup composite ${kitSetup}
        command kit_stop composite ${kitStop}
        command kit_grayscale_override js 'document.documentElement.style.filter = ""'
      '';
    xdg.configFile."tridactyl/autoclose.js".source =
      pkgs.runCommand "tridactyl-autoclose-build" { }
        "${pkgs.bun}/bin/bun build ${./tridactyl_autoclose.ts} --outfile=$out";
    xdg.configFile."tridactyl/grayscale.js".source =
      pkgs.runCommand "tridactyl-grayscale-build" { }
        "${pkgs.bun}/bin/bun build ${./tridactyl_grayscale.ts} --outfile=$out";
    xdg.configFile."tridactyl/location.example.js".source = ./tridactyl_location.js;

    # TODO: Set `network.proxy.allow_hijacking_localhost=true` (about:config)

    # remove after this: https://bugzilla.mozilla.org/show_bug.cgi?id=259356
    programs.firefox.policies = {
      # TODO: move everyone to `~/Downloads`, some tools just want to write to `~/Downloads` irrespective of your wish
      DefaultDownloadsDirectory = "\${home}/downloads";
    };

    programs.firefox.profiles."default" = {
      settings =
        {
          "sidebar.revamp" = true;
          "sidebar.verticalTabs" = true;
        }
        // lib.optionalAttrs (cfg.defaultContainer != null) {
          "kit.containers.default" = cfg.defaultContainer;
        };
      # containers = {
      #   personal = {
      #     color = "orange";
      #     icon = "fruit";
      #     id = 1;
      #   };
      #   random = {
      #     color = "yellow";
      #     icon = "cart";
      #     id = 2;
      #   };
      # };
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        tridactyl
        bitwarden
        dearrow
        sponsorblock
        rsshub-radar
        multi-account-containers

        # Currently missing
        # tab-wrangler
        # feedbro
      ];
    };
  };
}
