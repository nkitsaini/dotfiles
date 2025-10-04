{ ... }:
{
  services.open-webui.enable = false;

  # Doesn't get used anywhere (I think) but some library errors out using `Path.home()` in init
  services.open-webui.environment = {
    "HOME" = "/root";
  };
  services.open-webui.port = 8085; # collision with ipfs port
}
