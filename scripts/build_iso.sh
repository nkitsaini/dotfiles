#!/usr/bin/env bash
exec nix build .#nixosConfigurations.iso.config.system.build.isoImage
