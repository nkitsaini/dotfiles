# https://nixos.wiki/wiki/Sway
# I think most of this is unnecesary, but some variation makes screen sharing work on firefox. 
{ pkgs, ... }:
let
  # bash script to let dbus know about important env variables and
  # propagate them to relevent services run at the end of sway config
  # see
  # https://github.com/emersion/xdg-desktop-portal-wlr/wiki/"It-doesn't-work"-Troubleshooting-Checklist
  # note: this is pretty much the same as  /etc/sway/config.d/nixos.conf but also restarts  
  # some user services to make sure they have the correct environment variables
  dbus-sway-environment = pkgs.writeTextFile {
    name = "dbus-sway-environment";
    destination = "/bin/dbus-sway-environment";
    executable = true;

    text = ''
      dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
      systemctl --user stop pipewire pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr
      systemctl --user start pipewire pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr
    '';
  };

  # currently, there is some friction between sway and gtk:
  # https://github.com/swaywm/sway/wiki/GTK-3-settings-on-Wayland
  # the suggested way to set gtk settings is with gsettings
  # for gsettings to work, we need to tell it where the schemas are
  # using the XDG_DATA_DIR environment variable
  # run at the end of sway config
  configure-gtk = pkgs.writeTextFile {
    name = "configure-gtk";
    destination = "/bin/configure-gtk";
    executable = true;
    text = let
      schema = pkgs.gsettings-desktop-schemas;
      datadir = "${schema}/share/gsettings-schemas/${schema.name}";
    in ''
      gnome_schema=org.gnome.desktop.interface
      gsettings set $gnome_schema gtk-theme 'Dracula'
    '';
  };

in {
  # Ideally, I should mix this with home-manager config.
  # But don't want to figure out user stuff
  security.polkit.enable = true;
  security.pam.services.swaylock = { };
  programs.dconf.enable = true;

  hardware.graphics = {
    enable = true;
    # Added by nixos-hardware
    # driSupport = true;
    # driSupport32Bit = true;
    # extraPackages = with pkgs; [ rocmPackages.clr.icd ];
  }; # Should check for amd?

  ######### Not Part of sway-knobs
  # hardware.amdgpu.opencl = true;
  # hardware.amdgpu.loadInInitrd = true;
  ######### non-sway-knob end

  services.dbus.enable = true;
  services.gnome.gnome-keyring.enable = true;

  environment.systemPackages = with pkgs; [
    dbus # make dbus-update-activation-environment available in the path
    dbus-sway-environment
    configure-gtk


    # Use  env `WLR_RENDERER=vulkan` on related errors
    vulkan-validation-layers
  ];

  xdg.portal.config.common.default = "*";
  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal
    pkgs.xdg-desktop-portal-wlr
  ];
}
