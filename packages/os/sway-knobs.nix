{pkgs, ...}: {
  # Ideally, I should mix this with home-manager config.
  # But don't want to figure out user stuff
  security.polkit.enable = true;
  security.pam.services.swaylock = { };
  programs.dconf.enable = true;

  hardware.opengl.enable = true; # Should check for amd?

  xdg.portal.config.common.default = "*";
  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
}
