# Installs tools helpful for trying to run binaries/code meant for FHS-complaint systems. nix-ld should be silently helping in background. In rare-cases just run `fhs` and be dropped in fhs shell
{pkgs, ...}: {
  environment.systemPackages = [
  # TODO: use all libs from nix-ld.libraries definition
    (let
      base = pkgs.appimageTools.defaultFhsEnvArgs;
    in
      pkgs.buildFHSUserEnv (base
        // {
          name = "fhs";
          targetPkgs = pkgs: (base.targetPkgs pkgs) ++ [pkgs.pkg-config];
          profile = "export FHS=1";
          runScript = "fish";
          extraOutputsToInstall = ["dev"];
        }))
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.package = pkgs.nix-ld-rs;
  # Initially from: https://github.com/Mic92/dotfiles/blob/ce4d81790ac9111324b25d0b3fc5748d241f2f6f/nixos/modules/nix-ld.nix#L6
  programs.nix-ld.libraries = with pkgs; [
    curl
    dbus
    fuse3
    glib
    icu
    libGL
    libdrm
    libglvnd
    libnotify
    libpulseaudio
    libunwind
    libusb1
    libuuid
    libxkbcommon
    libxml2
    mesa
    nspr
    nss
    openssl
    pipewire
    stdenv.cc.cc
    systemd
    vulkan-loader
    xorg.libX11
    xorg.libXScrnSaver
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libxcb
    xorg.libxkbfile
    xorg.libxshmfence
    zlib
  ];
}
