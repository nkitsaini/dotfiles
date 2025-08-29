# Reference:
#  - https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/k3s/docs/CLUSTER_UPKEEP.md
#  - https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/k3s/docs/USAGE.md
#
# Use `kit-setup-k3s-config` to setup kubeconfig for current user.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.kit.services.k3s;

  kit-setup-k3s-config = pkgs.writeShellScriptBin "kit-setup-k3s-config" ''
    set -euo pipefail

    # Create .kube directory if it doesn't exist
    mkdir -p "$HOME/.kube"

    # Copy k3s kubeconfig to user's kube config
    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"

    # Change ownership to current user
    sudo chown "$USER" "$HOME/.kube/config"

    # Set appropriate permissions
    chmod 600 "$HOME/.kube/config"

    echo "Successfully copied k3s kubeconfig to ~/.kube/config"
  '';
in
{
  options.kit.services.k3s = {
    enable = mkEnableOption "k3s Kubernetes cluster";
  };

  config = mkIf cfg.enable {
    services.k3s = {
      enable = true;
      role = "server";
      manifests = {
        traefik-patch.source = ./traefik-patch.yaml;
      };
    };

    # Open required ports for k3s
    networking.firewall = {
      allowedTCPPorts = [
        6443 # k3s supervisor and Kubernetes API
        10250 # kubelet
      ];
      allowedUDPPorts = [
        8472 # flannel vxlan
      ];
    };

    # Ensure container runtime is available
    virtualisation.containerd.enable = mkDefault true;

    # Add the setup script to system packages
    environment.systemPackages = [ kit-setup-k3s-config ];

  };
}
