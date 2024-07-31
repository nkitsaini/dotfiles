# Most from: https://gist.github.com/qzm/a54559726896d5e6bf21adf2363ad334
{ config, pkgs, ... }:
let
  aria2_config = ''
    listen-port=60100-60200
    dht-listen-port=60100-60200
    max-connection-per-server=8
    min-split-size=8M
    split=8
    bt-request-peer-speed-limit=10M
  '';

  settingsDir = "${config.home.homeDirectory}/.aria2_rpc";
  rpcSecretFile = "${settingsDir}/rpc_secret.txt";
  sessionFile = "${settingsDir}/aria2.session";
  rpcConfigFile = "${settingsDir}/aria2.conf";
  downloadDir = "${config.home.homeDirectory}/Downloads/aria2";
  configFile = pkgs.writeTextFile {
    name = "aria2.conf";
    text = aria2_config;
  };
   
  servicePre = (pkgs.writeScriptBin "pre.sh" ''
      #!${pkgs.bash}/bin/bash
      set -e
      ${pkgs.coreutils}/bin/mkdir -p "${settingsDir}"
      ${pkgs.coreutils}/bin/mkdir -p "${downloadDir}"
      ${pkgs.coreutils}/bin/touch "${sessionFile}"
      ${pkgs.coreutils}/bin/cat "${configFile}" > "${rpcConfigFile}"
      ${pkgs.coreutils}/bin/echo "rpc-secret=$(${pkgs.coreutils}/bin/cat "${rpcSecretFile}")" >> "${rpcConfigFile}"
    '');


in {
  programs.aria2 = {
    enable = true;
    extraConfig = aria2_config;
  };

  # Closely mirrors: https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/networking/aria2.nix
  systemd.user.services.aria2-rpc = {
    Unit = { Description = "Aria2 RPC Server"; };
    Install = { WantedBy = [ "default.target" ]; };
    Service = {
      Restart = "on-failure";
      ExecStartPre = ''${servicePre}/bin/pre.sh'';
      ExecStart = ''
        ${pkgs.aria2}/bin/aria2c "--dir=${downloadDir}" --enable-rpc --rpc-listen-port=60001 --rpc-listen-all --rpc-allow-origin-all --conf-path "${rpcConfigFile}" "--save-session=${sessionFile}"'';
    };
  };
}
