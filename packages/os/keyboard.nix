{ pkgs, ... }: {
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  environment.etc."dual-function-keys.yaml".text = ''
    TIMING:
      TAP_MILLISEC: 200
      DOUBLE_TAP_MILLISEC: 0

    MAPPINGS:
      - KEY: KEY_CAPSLOCK
        TAP: KEY_ESC
        HOLD: KEY_LEFTCTRL
      - KEY: KEY_LEFTALT
        TAP: KEY_LEFTMETA
        HOLD: KEY_LEFTMETA
      - KEY: KEY_LEFTMETA
        TAP: KEY_LEFTALT
        HOLD: KEY_LEFTALT
  '';
  environment.etc."swaps.yaml".text = ''
    TIMING:
      TAP_MILLISEC: 0
      DOUBLE_TAP_MILLISEC: 0

    MAPPINGS:
      - KEY: KEY_LEFTALT
        TAP: KEY_LEFTMETA
        HOLD: KEY_LEFTMETA
      - KEY: KEY_LEFTMETA
        TAP: KEY_LEFTALT
        HOLD: KEY_LEFTALT
  '';
  services.interception-tools = {
    enable = true;
    plugins = [ pkgs.interception-tools-plugins.dual-function-keys ];
    udevmonConfig = ''
      - JOB: "${pkgs.interception-tools}/bin/intercept -g $DEVNODE | ${pkgs.interception-tools-plugins.dual-function-keys}/bin/dual-function-keys -c /etc/dual-function-keys.yaml | ${pkgs.interception-tools}/bin/uinput -d $DEVNODE"
        DEVICE:
          EVENTS:
            EV_KEY: [KEY_CAPSLOCK]

      - JOB: "${pkgs.interception-tools}/bin/intercept -g $DEVNODE | ${pkgs.interception-tools-plugins.dual-function-keys}/bin/dual-function-keys -c /etc/swaps.yaml | ${pkgs.interception-tools}/bin/uinput -d $DEVNODE"
        DEVICE:
          EVENTS:
            EV_KEY: [KEY_LEFTMETA, KEY_LEFTALT]
    '';
  };

}
