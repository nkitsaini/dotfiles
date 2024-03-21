{ modulesPath, pkgs, lib, ... }: {

  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # use the latest Linux kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Needed for https://github.com/NixOS/nixpkgs/issues/58959
  boot.supportedFilesystems =
    lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" ];

  environment.systemPackages = with pkgs; [
    tmux
    git
    fish
    neovim
    helix
    bitwarden-cli

    (pkgs.writeScriptBin "nixc-install-ssh-authorized-keys" ''
      #!${pkgs.bash}/bin/bash
      ${pkgs.curl}/bin/curl "https://github.com/nkitsaini.keys" > ~/.ssh/authorized_keys
    '')

    (pkgs.writeScriptBin "nixc-clone-dotfiles" ''
      #!${pkgs.bash}/bin/bash
      ${pkgs.git}/bin/git close https://github.com/nkitsaini/dotfiles.git ~/code/dotfiles
    '')

    (pkgs.writeScriptBin "nixc-generate-hardware-config" ''
      #!${pkgs.bash}/bin/bash
      nixos-generate-config --show-hardware-config --no-filesystems
    '')

    (pkgs.writeScriptBin "nixc-readme" ''
      #!${pkgs.coreutils-full}/bin/cat
      Use commands starting with `nixc` to manage stuff.
    '')
  ];

  networking.wireless.enable = false;
  networking.wireless.iwd.enable = true;
}
