# nixos-rebuild
Use --target-host to build locally and deploy on crane. This is much faster if the remote host is slower.

Run on local machine: `nixos-rebuild switch --flake .#crane --target-host user@ip`

## Migration
If migrating from one host to other, following services should be taken care of.
- just general backup of downloads etc.
- headscale (need to preserve keys/auth)
- docker registry (might need to preserve images)
- docker swarm - this is harder, but generally
  - Backup all the docker volumes (named/unnamed)
  - see which services are running and follow there specific guides



## Services
### Docker swarm:

```
# On server
docker swarm init --advertise-addr 127.0.0.1

# On client
docker context create prod --docker "host=ssh://user@host"

# usage:
docker --context prod service --help
```

#### Caddy setup
- https://github.com/lucaslorentz/caddy-docker-proxy
```
# as docker context `prod`
docker network create caddy --scope swarm

# deploy caddy service
docker stack deploy -c docker_swarm_setup/caddy/docker-compose.yml caddy


# Deploy any service you want
docker stack deploy -c docker_swarm_setup/dummy_whoami_compose.yml caddy
  
```
