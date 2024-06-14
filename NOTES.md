1. internet not working in ISO
2. sway-bg not working
  Jun 12 00:38:10 deepak systemd[1915]: sway-bg.service: Main process exited, code=exited, status=1/FAILURE
  Jun 12 00:38:10 deepak systemd[1915]: sway-bg.service: Failed with result 'exit-code'.
  Jun 12 00:38:10 deepak systemd[1915]: sway-bg.service: Scheduled restart job, restart counter is at 5.
  Jun 12 00:38:10 deepak systemd[1915]: sway-bg.service: Start request repeated too quickly.
  Jun 12 00:38:10 deepak systemd[1915]: sway-bg.service: Failed with result 'exit-code'.
  Jun 12 00:38:10 deepak systemd[1915]: Failed to start Set sway background.
3. Add command for substituter
  - nix-server -p 8004 (on host)
  - nixos-install ... --substituters http://<ip>:8004?trusted=1
4. Start sway automatically
5. GUI for bluetooth, GUI for iwctl, GUI for screenshot



nmtui-connect:
  secrets were required but not provided (but worked through applet)

~/.xsession got stuck, but worked after starting hm-session-manager.service

