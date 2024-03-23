{ pkgs, lib, ... }: {

  imports = [
    ./graphical-base.nix
    ../../packages/os/kernel.nix
    ../../packages/os/ssh.nix
    ../../packages/os/sound.nix
    ../../packages/os/keyboard.nix
    ../../packages/os/network-desktop.nix
    ../../packages/os/fonts.nix
    ../../packages/os/core.nix
  ];

  # not sure?
  services.xserver.windowManager.i3 = { enable = true; };

  users.users.nixos = {
    openssh.authorizedKeys.keys = import ../../packages/authorized_keys.nix;
  };
  users.users.root = {
    openssh.authorizedKeys.keys = import ../../packages/authorized_keys.nix;
  };

  # Needed for https://github.com/NixOS/nixpkgs/issues/58959
  boot.supportedFilesystems =
    lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" ];

  home-manager.users.nixos = import ./home.nix;

  environment.systemPackages = with pkgs; [
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

}
