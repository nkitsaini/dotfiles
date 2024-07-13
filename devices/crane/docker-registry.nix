{config, ...}: let
  domain = "dr.nkit.dev";
in {

  # MIGRATION/BACKUP GUIDE:
  #     If you don't want older images, no care is required. If you want to preserve images copy /var/lib/docker-registry to new host.
  # 

  # This can be moved inside k3s, but more reliable here until kubenix is stable I guess.
  services = {
    dockerRegistry = {
      enable = true;
      port = 5000;
      enableGarbageCollect = true;
      garbageCollectDates = "weekly";
    };

    caddy.virtualHosts.${domain}.extraConfig = ''
      basic_auth {
         # hint: Everything is same but louder
      	kit $2a$14$iA29aDdzx.ORB//9orpdr.1QsvjmafjnGmbgZ7U/aggI5jqXuAwEK
      }
       reverse_proxy http://localhost:${toString config.services.dockerRegistry.port}
    '';
  };
}
