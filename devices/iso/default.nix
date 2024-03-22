{ pkgs, lib, ... }: {

  imports = [
    ./graphical-base.nix
    ../../packages/os/kernel.nix
    ../../packages/os/ssh.nix
    ../../packages/os/sound.nix
    ../../packages/os/keyboard.nix
    ../../packages/os/locale_in.nix
    ../../packages/os/network-desktop.nix
    # ../../packages/os/sway-knobs.nix
    ../../packages/os/fonts.nix
    ../../packages/os/shell-minimal.nix
  ];

  # not sure?
  services.xserver.windowManager.i3 = { enable = true; };

  # Needed for https://github.com/NixOS/nixpkgs/issues/58959
  boot.supportedFilesystems =
    lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" ];

  networking.useNetworkd = true;
  systemd.network.networks."40-wired" = {
    matchConfig = { Name = pkgs.lib.mkForce "enp* eth*"; };
    DHCP = "yes";
  };

  # users.users.iso = {
  #   isNormalUser = true;
  #   description = "ISO";
  #   extraGroups = [
  #     "networkmanager"
  #     "wheel"
  #     "video"
  #   ]; # "video" is required for brightness control
  #   packages = with pkgs;
  #     [
  #       firefox
  #       #  thunderbird
  #     ];
  # };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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
