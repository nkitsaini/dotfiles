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
  - `sudo apt install slurp` (to allow selecting monitor while sharing screen)
      - We also install it in home-manager, but the systemd service xdg-desktop-portal-wlr can't access it unless it's installed globally in /usr/bin or something

- Change the `/usr/bin/firefox` to point to firefox from nix. Otherwise dbus openURI doesn't work.
  - `mv /usr/bin/firefox /usr/bin/firefox.bak`
  - `ln -s /home/<username>/.nix-profile/bin/firefox /usr/bin/firefox`

```sh
# Test by running
gdbus call --session \
        --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop \
        --method org.freedesktop.portal.OpenURI.OpenURI \
        "" \
        "https://example.com" \
        {}
```

- restart to let things like .desktop discovery take effect
