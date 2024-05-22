{...}: {
  networking.firewall.allowedTCPPorts = [ 6443 80 443 ];
  networking.firewall.allowedUDPPorts = [ 6443 ];
  services.k3s.enable = true;

environment.etc."rancher/k3s/registries.yaml".text = ''
mirrors:
  oogway:5000:
    endpoint:
      - "http://oogway:5000"
'';
  
}
