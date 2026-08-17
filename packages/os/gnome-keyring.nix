{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gnome.gnome-keyring;
in
{
  # Upstream currently hard-codes pkgs.gnome-keyring. Keep the same NixOS
  # integration, but add a package option so this bug fix does not overlay the
  # entire package set and rebuild unrelated consumers.
  disabledModules = [ "services/desktops/gnome/gnome-keyring.nix" ];

  options.services.gnome.gnome-keyring = {
    enable = lib.mkEnableOption "GNOME Keyring daemon";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./gnome-keyring-package.nix { inherit pkgs; };
      description = "GNOME Keyring package used by the system integration.";
    };
  };

  config = lib.mkMerge [
    { services.gnome.gnome-keyring.enable = true; }
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];

      services.dbus.packages = [
        cfg.package
        pkgs.gcr
      ];

      xdg.portal.extraPortals = [ cfg.package ];
      security.pam.services.login.enableGnomeKeyring = true;

      security.wrappers.gnome-keyring-daemon = {
        owner = "root";
        group = "root";
        capabilities = "cap_ipc_lock=ep";
        source = "${cfg.package}/bin/gnome-keyring-daemon";
      };
    })
  ];
}
