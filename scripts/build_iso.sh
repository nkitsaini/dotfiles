#!/usr/bin/env bash
exec nix build .#iso.config.system.build.isoImage
