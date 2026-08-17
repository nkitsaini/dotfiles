rec {

  description = "Home Manager configuration of ankit";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    kit = {
      url = "path:modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    volume_control_rs = {
      url = "path:softwares/volume_control";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };

    markdown_lsp = {
      url = "path:softwares/markdown_lsp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    radioctl = {
      url = "path:softwares/radioctl";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    karo = {
      url = "path:softwares/karo";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      home-manager,
      nur,
      disko,
      ...
    }@inputs:
    let
      # cli-helpers tests fail upstream (ANSI escape code mismatch); disable to unblock build.
      # Needed in both `pkgs` (for homeConfigurations) and `nixpkgs.overlays` (for nixosConfigurations).
      cliHelpersOverlay = final: prev: {
        python313Packages = prev.python313Packages.overrideScope (pyFinal: pyPrev: {
          cli-helpers = pyPrev.cli-helpers.overridePythonAttrs { doCheck = false; };
        });
      };

      mkSystem =
        {
          hostname,
          extraModules ? [ ],
          autoIncludeDeviceModule ? true,
          username ? "kit",
        }:
        nixpkgs.lib.nixosSystem {
          # NOTE: Change this to aarch64-linux if you are on ARM
          inherit system;
          specialArgs = {
            inherit inputs;
            inherit system;
            inherit hostname;
            inherit username;
          };
          modules = [
            home-manager.nixosModules.home-manager
            inputs.nur.modules.nixos.default
            disko.nixosModules.disko
            inputs.kit.nixosModules.default
            (
              { inputs, ... }:
              {
                nix.settings = {
                  substituters = nixConfig.extra-substituters;
                  trusted-public-keys = nixConfig.extra-trusted-public-keys;
                };

                nixpkgs.overlays = [ cliHelpersOverlay ];

                home-manager.sharedModules = [
                  inputs.kit.hm.default
                ];

              }
            )
          ]
          ++ extraModules
          ++ (if (autoIncludeDeviceModule) then [ ./devices/${hostname} ] else [ ]);

        };

      system = "x86_64-linux";
      pkgs = import nixpkgs {
        system = system;
        overlays = [
          inputs.nur.overlays.default
          inputs.nixgl.overlay
          cliHelpersOverlay
        ];
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };
      # Do not overlay the whole standalone package set: Home Manager exposes a
      # package option, so only its keyring service needs the patched package.
      patchedGnomeKeyring = import ./packages/os/gnome-keyring-package.nix { inherit pkgs; };

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          git-crypt
        ];
      };

      # Interactive/automated debugging VM (boots a real device config). Run:
      #   nix build .#checks.x86_64-linux.vm-debug              (automated)
      #   nix run   .#checks.x86_64-linux.vm-debug.driverInteractive  (manual)
      # See .agents/skills/nixos-vm-testing/SKILL.md for the iteration workflow.
      checks.${system} = {
        gnome-keyring-open-session =
          let
            nixosKeyringEnabled = self.nixosConfigurations.monkey.config.services.gnome.gnome-keyring.enable;
            nixosKeyringPackage = self.nixosConfigurations.monkey.config.services.gnome.gnome-keyring.package;
            nixosHomeManagerKeyringEnabled =
              self.nixosConfigurations.monkey.config.home-manager.users.kit.services.gnome-keyring.enable;
            standaloneHomeManagerKeyringEnabled =
              self.homeConfigurations.shifu.config.services.gnome-keyring.enable;
            standaloneHomeManagerKeyringPackage =
              self.homeConfigurations.shifu.config.services.gnome-keyring.package;
          in
          assert nixosKeyringEnabled;
          assert nixosKeyringPackage.outPath == patchedGnomeKeyring.outPath;
          assert !nixosHomeManagerKeyringEnabled;
          assert standaloneHomeManagerKeyringEnabled;
          assert standaloneHomeManagerKeyringPackage.outPath == patchedGnomeKeyring.outPath;
          pkgs.runCommand "gnome-keyring-open-session-regression"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.dbus
                pkgs.gnugrep
                pkgs.systemd
              ];
            }
            ''
              test_root="$TMPDIR/keyring-test"
              mkdir -p "$test_root/home" "$test_root/runtime"
              chmod 700 "$test_root/runtime"

              export HOME="$test_root/home"
              export XDG_RUNTIME_DIR="$test_root/runtime"
              # Prevent D-Bus from activating the unwrapped NixOS service; the
              # test starts this flake's patched daemon directly below.
              export XDG_DATA_DIRS=/nonexistent

              {
                read -r dbus_address
                read -r dbus_pid
              } < <(
                dbus-daemon \
                  --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
                  --fork --print-address=1 --print-pid=1
              )
              export DBUS_SESSION_BUS_ADDRESS="$dbus_address"

              daemon_log="$TMPDIR/gnome-keyring.log"
              ${patchedGnomeKeyring}/bin/gnome-keyring-daemon \
                --start --foreground --components=secrets \
                >"$daemon_log" 2>&1 &
              daemon_pid=$!

              cleanup() {
                if kill -0 "$daemon_pid" 2>/dev/null; then
                  kill "$daemon_pid"
                  wait "$daemon_pid" || true
                fi
                if kill -0 "$dbus_pid" 2>/dev/null; then
                  kill "$dbus_pid"
                fi
              }
              trap cleanup EXIT

              for attempt in $(seq 1 100); do
                if busctl --user list 2>/dev/null | grep -q org.freedesktop.secrets; then
                  break
                fi
                sleep 0.05
              done
              busctl --user list | grep -q org.freedesktop.secrets

              # A no-reply call disconnects before the handler runs. This
              # deterministically aborted unpatched gnome-keyring 50.0.
              for attempt in $(seq 1 100); do
                busctl --user --expect-reply=no call \
                  org.freedesktop.secrets \
                  /org/freedesktop/secrets \
                  org.freedesktop.Secret.Service OpenSession \
                  sv dh-ietf1024-sha256-aes128-cbc-pkcs7 ay 1 2 \
                  >/dev/null 2>&1 || true
              done

              sleep 1
              if ! kill -0 "$daemon_pid" 2>/dev/null; then
                cat "$daemon_log"
                exit 1
              fi
              if grep -Eq "assertion.*failed|GLib-ERROR" "$daemon_log"; then
                cat "$daemon_log"
                exit 1
              fi

              touch "$out"
            '';
        vm-debug = import ./tests/vm-debug.nix {
          inherit
            pkgs
            inputs
            system
            home-manager
            nur
            disko
            ;
          lib = pkgs.lib;
        };
        karo-fish-completion =
          let
            hm = self.homeConfigurations.shifu.config;
            completions = "${hm.home.path}/share/fish/vendor_completions.d";
            karo-e2e = inputs.karo.checks.${system}.fish-completion;
          in
          assert pkgs.lib.hasInfix "/share/fish/vendor_completions.d"
            hm.programs.fish.interactiveShellInit;
          pkgs.runCommand "karo-home-manager-fish-completion" { } ''
            test -f "${completions}/karo.fish"
            test -e "${karo-e2e}"
            touch "$out"
          '';
      };
      # ===== Home-manager only configs
      homeConfigurations."shifu" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./devices/shifu/home.nix
          inputs.kit.hm.default
          {
            # Ubuntu has no NixOS keyring/PAM module, so Home Manager owns the
            # user service and starts the same crash-guarded daemon.
            services.gnome-keyring.package = patchedGnomeKeyring;
          }
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;

          # wezterm didn't work with only vulkan, zed didn't work with only GL.
          # But can't include vulkan as it can break non-gui packages due to llvm lib in `LD_LIBRARY_PATH`. So open-gl globally, and vulkan for specific packages after: https://github.com/nix-community/home-manager/pull/5355, right now it is manual: `nixgl-vulkan-run ....`
          nixGLCommandPrefix = "${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel  ";
          disableSwayLock = true;
        };
      };
      homeConfigurations."shifu_remote" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./devices/shifu_remote/home.nix
          inputs.kit.hm.default
        ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
        };
      };

      # ===== Nixos configs
      nixosConfigurations.monkey = mkSystem {
        hostname = "monkey";
        extraModules = [ nixos-hardware.nixosModules.lenovo-thinkpad-e14-amd ];
      };
      nixosConfigurations.iso = mkSystem { hostname = "iso"; };

      nixosConfigurations.deepak = mkSystem {
        hostname = "deepak";
        username = "deepak";
      };
      nixosConfigurations.akanksha = mkSystem {
        hostname = "akanksha";
        username = "akanksha";
      };

      # TODO: disko config remaining
      nixosConfigurations.oogway = mkSystem { hostname = "oogway"; };

      # TODO: following configs to be in similar fashion as `monkey`
      # i.e.
      # 1. use fixed users,
      # 2. rename configuration.nix -> default.nix
      # 3. have home-manager config imported through default.nix
      # 4. manage disk through disko
      # ... or something I missed
      nixosConfigurations.crane = mkSystem {
        hostname = "crane";
        autoIncludeDeviceModule = false;
        extraModules = [ ./devices/crane ];
      };
    };
  nixConfig = {
    extra-substituters = [ "https://helix.cachix.org" ];
    extra-trusted-public-keys = [ "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs=" ];
  };
}
