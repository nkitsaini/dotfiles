{ pkgs, config, ... }:
let
  meditationDirectory = "${config.home.homeDirectory}/code/shoal/meditation_bell_trigger";
  meditationTrigger = (pkgs.writeShellApplication {
    name = "meditation-bell-trigger";
    runtimeInputs = [ pkgs.nix pkgs.git pkgs.libnotify ];
    # TODO: move to nix based build
    text = ''
      cd ${meditationDirectory}
      ${pkgs.uv}/bin/uv run -m meditation_bell_trigger.laptop
    '';
  });
in {
  systemd.user.services.meditation-bell-trigger = {
    Unit = { Description = ""; };
    Install = { WantedBy = [ "default.target" ]; };
    Service = {
      ExecStart = "${meditationTrigger}/bin/meditation-bell-trigger";
      Restart = "on-failure";
    };
  };
}
