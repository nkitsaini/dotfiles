{pkgs_working_openwebui, ...}: {
      services.open-webui.enable=true;
      services.open-webui.package = pkgs_working_openwebui.open-webui;
}
