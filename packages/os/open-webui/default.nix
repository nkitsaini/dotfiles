{pkgs_working_openwebui, ...}: {
      services.open-webui.enable=true;
      services.open-webui.package = pkgs_working_openwebui.open-webui;

      # Doesn't get used anywhere (I think) but some library errors out using `Path.home()` in init
      services.open-webui.environment = {"HOME"="/root";};
      services.open-webui.port = 8085; # collision with ipfs port
}
