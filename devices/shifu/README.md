Steps:
- Install nix
- Add following line to `/etc/nix/nix.conf`
  `experimental-features = nix-command flakes`
- Run 
  `nix run home-manager/master -- init --flake /home/asaini/code/dotfiles/#shifu`
  `nix run home-manager/master -- switch --flake /home/asaini/code/dotfiles/#shifu`
- To run gui programs use (after lates steps it won't be required):
  `nixgl-run <program>`

- follow `~/.home-manager-extras/README.md` to enable window manager

- install fonts from 'packages/os/fonts.nix'
  - from apt: `sudo apt install fonts-font-awesome fonts-noto-mono fonts-noto-cjk-extra fonts-noto-extra fonts-noto-color-emoji`
  - Download nerd font from `https://www.nerdfonts.com/font-downloads` and put inside ~/.fonts
  - Run `fc-cache -fv`

- install packages from `packages/os/sway/sway-knobs.nix` (to support screen sharing and stuff)
  - `sudo apt install xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk`

- restart to let things like .desktop discovery take effect
