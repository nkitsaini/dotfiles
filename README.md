My nix configs.
Some parts are heavily inspired by [archseer's config](https://github.com/archseer/snowflake).


To deploy to low resource machines which can't build the packages themselves run:
```
# Run from a powerful machine where --target-host points to machine where you want to deploy. Make sure you have access to target host
nixos-rebuild switch --flake ~/code/dotfiles#crane --target-host root@116.203.178.188
```
