# nixos-rebuild
Use --target-host to build locally and deploy on crane. This is much faster.

Run on local machine: `nixos-rebuild switch --flake .#crane --target-host user@ip`



## Docker swarm:

```
# On server
docker swarm init --advertise-addr 127.0.0.1

# On client
docker context create prod --docker "host=ssh://user@host"

# usage:
docker --context prod service --help
```

### Caddy setup
- https://github.com/lucaslorentz/caddy-docker-proxy
```
# as docker context `prod`
docker network create caddy --scope swarm

# deploy caddy service
docker stack deploy -c docker_swarm_setup/caddy/docker-compose.yml caddy


# Deploy any service you want
docker stack deploy -c docker_swarm_setup/dummy_whoami_compose.yml caddy
  
```
