# non-gui stuff
{
  config,
  pkgs,
  inputs,
  nixGLCommandPrefix ? "",
  ...
}:
{
  imports = [
    # inputs.nur.homeManager.default
    # inputs.nur.hmModules.nur
    ./shell
    ./tms
    ./helix
    ./xdg_config.nix
    ./yt-dlp.nix
    ./vcs.nix
    ./yazi.nix
    ./syncthing.nix
    ./cmus
    ./aria2
    ./neovim
    ./taskwarrior
    # ../../modules/hm
  ];

  kit.blocks = {
    dev-cli.enable = true;
  };

  # kit.neovim.enable = true;
  # username and home directory are provided by the parent home.nix

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  nixpkgs.config.allowUnfree = true;
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
  };
  systemd.user.enable = true;
  systemd.user.startServices = true;

  programs.gh.enable = true;

  programs.ssh.enable = true;
  programs.ssh.enableDefaultConfig = false;
  services.ssh-agent.enable = true;

  programs.feh.enable = true;

  # Stores configs I don't want to be in Nix
  programs.ssh.matchBlocks."*" = {
    forwardAgent = false;
    addKeysToAgent = "no";
    compression = false;
    serverAliveInterval = 0;
    serverAliveCountMax = 3;
    hashKnownHosts = false;
    userKnownHostsFile = "~/.ssh/known_hosts";
    controlMaster = "no";
    controlPath = "~/.ssh/master-%r@%n:%p";
    controlPersist = "no";
  };
  programs.ssh.includes = [ "${config.home.homeDirectory}/.ssh/user_config" ];

  programs.ripgrep = {
    enable = true;
    arguments = [ "-S" ];
  };

  programs.bottom = {
    enable = true;
    settings = {
      flags = {
        color = "gruvbox-light";
      };
    };
  };

  programs.bat = {
    enable = true;
    config = {
      pager = "delta";
      theme = "gruvbox-light";
    };
  };

  programs.tealdeer = {
    enable = true;
    settings = {
      updates = {
        auto_update = true;
      };
    };
  };
  programs.gitui.enable = true;
  programs.gitui.keyConfig = builtins.readFile ./gitui_keybindings.ron;

  programs.nix-index = {
    enable = true;
  };

  services.batsignal = {
    enable = true;
  };
  services.network-manager-applet.enable = true;

  xdg.configFile."nixpkgs/config.nix".text = ''
     {
      packageOverrides = pkgs: {
        nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
          inherit pkgs;
        };
      };
    }
  '';

  home.file.".cargo/config.toml".text = ''
    [registries.crates-io]
    protocol = "sparse"
    [target.x86_64-unknown-linux-gnu]
    linker = "${pkgs.clang}/bin/clang"

    # --no-rosegment -> required for cargo-flamegraph
    rustflags = ["-Clink-arg=--ld-path=${pkgs.mold}/bin/mold", "-Clink-arg=-Wl,--no-rosegment"]
  '';

  # Home Directories
  home.file."external/.keep".text = ""; # External repos
  home.file."code/.keep".text = ""; # Personal repos
  home.file."workspace/.keep".text = ""; # Work repos
  home.file."mnt/.keep".text = ""; # mount points
  home.file."tmp/.keep".text = ""; # temporary directory
  home.file."music/.keep".text = ""; # temporary directory
  home.file."videos/.keep".text = ""; # temporary directory
  home.file."Downloads/.keep".text = ""; # downloads directory
  home.file."pictures/.keep".text = ""; # downloads directory

  programs.eza = {
    enable = true;
  };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages =
    with pkgs;
    let
      # Helper function to create a script that builds and runs a shoal project
      mkShoalScript =
        name: projectPath:
        writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.fd ];
          text = ''
            tool_dir="${config.home.homeDirectory}/code/shoal/${projectPath}"

            root_link="$tool_dir/result-app"
            result_bin="$tool_dir/result-bin"
            rebuild=0

            # 1. Check if the GC root link exists at all
            if [ ! -L "$root_link" ] || [ ! -L "$result_bin" ]; then
                rebuild=1
            else
                # 2. Check if any file is newer than the result link.
                #    We use fd to respect .gitignore and check timestamps efficiently.

                # Get the mtime of the symlink itself
                link_time=$(stat -c %Y "$root_link")

                # fd --changed-after checks timestamps internally and respects .gitignore
                # We exclude result* symlinks explicitly
                # We pipe to head -n 1 to stop at the first match (lazy check)
                newer_file=$(fd --type f --exclude 'result*' --changed-after "@$link_time" . "$tool_dir" | head -n 1)

                if [ -n "$newer_file" ]; then
                    rebuild=1
                fi
            fi

            # 3. If a rebuild is triggered (or first run)
            if [ "$rebuild" -eq 1 ]; then
                echo "🔄 Source changed or no root found. Rebuilding..." >&2

                # Calculate the system type once
                system=$(nix eval --raw --impure --expr builtins.currentSystem)

                # We create a wrapper derivation that depends on the flake app's program.
                # This forces Nix to build exactly what 'nix run' would run (including dependencies),
                # and allows us to create a persistent GC root for it.
                nix build --impure --expr "
                let
                  pkgs = import <nixpkgs> {};
                  flake = builtins.getFlake \"$tool_dir\";
                  program = flake.apps.\"$system\".default.program;
                in
                  pkgs.runCommand \"shoal-gc-root\" {} '''
                    mkdir -p \$out/bin
                    ln -s \''${program} \$out/bin/run
                  '''
                " --out-link "$root_link" > /dev/null

                # Resolve the actual binary path from the wrapper
                prog=$(readlink -f "$root_link/bin/run")

                # Create a symlink to the binary for direct execution
                ln -sf "$prog" "$result_bin"
            fi

            # 4. Run the cached binary (use the symlink to the actual binary)
            exec "$result_bin" "$@"
          '';
        };
    in
    [
      # # Adds the 'hello' command to your environment. It prints a friendly
      # # "Hello, world!" when run.

      # Nix specific
      difftastic

      # For yazi
      yazi
      unar
      exiftool
      # mpv
      mediainfo

      cmake

      # httpie in rust
      xh

      # hello
      # qbittorrent
      xclip
      jq
      fd
      killall
      jless
      hexyl
      zip
      unzip
      gnutar

      (pkgs.rustup.overrideAttrs (old: {
        # do not run rustup tests if cache is missing. They take forever.
        doCheck = false;
      }))

      qrencode
      s3fs
      gcc
      python312
      python312Packages.ipython
      python312Packages.pipx
      python312Packages.tkinter # for turtle
      sd
      rsync
      nmap
      minio-client
      ffmpeg
      restic
      rclone
      ddcutil
      tmux
      # tmuxp is broken
      # tmuxp
      just
      grc
      fzf
      cargo-cross
      hyperfine
      bun
      deno
      ncdu
      dua # ncdu alternative
      caddy
      archivemount
      ethtool
      uv
      file
      lsof
      ntfs3g
      openssl
      iperf

      # Utils
      pv
      pdftk
      hwinfo
      beep
      ascii

      # Code specific
      nixfmt-rfc-style
      ruff
      lazygit
      nodePackages.nodejs
      (writeScriptBin "notes" ''
        #!${pkgs.dash}/bin/dash
        cd ${config.home.homeDirectory}/code/notes

        # HACK: without `:e` otherwise norg doesn't load on default file
        exec nvim -c ':e'
      '')
      (writeShellApplication {
        name = "yt-dlp";

        # 1. List packages here to add them to the script's PATH
        runtimeInputs = [
          pkgs.deno
          pkgs.uv
        ];

        # 2. Write your script usually. Commands from the inputs above will just work.
        text = ''
          exec ${pkgs.uv}/bin/uv tool run --with secretstorage --python 3.12 --with httpx --with requests --prerelease explicit yt-dlp@latest "$@"
        '';
      })
      (writeScriptBin "copilot" ''
        #!${pkgs.dash}/bin/dash
        exec ${nodePackages.nodejs}/bin/node ${vimPlugins.copilot-vim}/dist/agent.js
      '')

      (mkShoalScript "audiobook_generator" "audiobook_generator")
      (mkShoalScript "hh" "helios_helper")
      (mkShoalScript "bw-util" "bitwarden_util")
      (mkShoalScript "notes-util" "notes_utils")
      (mkShoalScript "audio_cleaner" "audio_cleaner")
      (mkShoalScript "mit_ocw_utils" "mit_ocw_utils")
      (mkShoalScript "make_public" "make_public")
      (mkShoalScript "cuckoo_controller" "cuckoo_controller")

      # I3 specific
      trashy
      jc # convert common command outputs to json

      # MTP
      jmtpfs

      # From old fish history
      acpi
      rqbit
      asciinema
      bandwhich
      bc
      bear
      biome
      bitwarden-cli
      dig
      delve
      duckdb
      fortune
      gdb
      gen-license
      hexyl
      htop
      httpie
      iperf3
      gnumake
      pkg-config
      hwatch
      hyperfine
      mold
      tmate
      tailscale
      libnotify
      iptables
      bruno
      tree
      broot
      podman
      podman-compose
      sqlite
      litecli
      pgcli
      tokei
      valgrind
      wget
      duf # better df

      # btrfs

      # Broken: https://github.com/NixOS/nixpkgs/issues/336006
      # compsize

      sshfs

      binutils
      curl
      usbutils # lsusb
      lshw
      dosfstools
      powertop
      iputils
      # moreutils
      nmap
      util-linux
      whois
      # Kernel modules
      # TODO: enable when on NixOS
      # linuxKernel.packages.linux_6_7.ddcci-driver

      # # It is sometimes useful to fine-tune packages, for example, by applying
      # # overrides. You can do that directly here, just don't forget the
      # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
      # # fonts?
      # (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

      # # You can also create simple shell scripts directly inside your
      # # configuration. For example, this adds a command 'my-hello' to your
      # # environment:
      # (writeShellScriptBin "my-hello" ''
      #   echo "Hello, ${config.home.username}!"
      # '')
    ]
    ++ (import ../shared/core_deps.nix) pkgs; # NOTE: include the version below if this gives error on environment with nixos configuration.
  # Include core-deps in home-manager if we are not inside nixos configuration
  # otherwise these will get included in nixos configuration itself
  # ++ (if (config ? nixosVersion) then [] else ((import ../shared/core_deps.nix) pkgs));

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ankit/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    LC_ALL = "en_US.UTF-8";
    LANG = "en_US.UTF-8";
    NIXPKGS_ALLOW_UNFREE = "1";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
