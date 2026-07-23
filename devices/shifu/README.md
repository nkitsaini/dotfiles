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
  - Download Noto font from `https://www.nerdfonts.com/font-downloads` and put inside ~/.fonts
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
- Install wireplumber for wpctl to work (used for volume_control_rs script)
```
sudo apt install wireplumber pipewire-audio-client-libraries libspa-0.2-bluetooth
systemctl --user --now enable wireplumber.service 
systemctl --user restart pipewire pipewire-pulse wireplumber 
```

- Allow DDC/CI control of external monitors without sudo. Needed by
  `monitorctl` (`packages/hm/monitorctl`), which the sway brightness keys use:
  when the cursor is on an external monitor, fn+f5/f6 change *its* brightness
  over the i2c bus instead of the laptop backlight. On NixOS hosts this is
  covered by `hardware.i2c.enable` (packages/os/core.nix) + the `i2c`
  extraGroup (users/kit); on ubuntu it's manual:
```sh
# make sure the i2c char devices exist now and after reboots
sudo modprobe i2c-dev
echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf

# let the i2c group access /dev/i2c-* and join it
sudo groupadd --system i2c
sudo usermod -aG i2c "$USER"
echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | sudo tee /etc/udev/rules.d/45-ddcutil-i2c.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=i2c-dev

# log out and back in (group membership), then verify:
ddcutil detect     # should list the external monitor, no sudo
monitorctl list    # should show the monitor with "ddc/ci on i2c bus N"
```
  If `ddcutil detect` finds nothing, check the monitor's OSD menu - some
  monitors ship with DDC/CI turned off.

- Silence the recurring "Some required themes are missing" notification. It
  comes from the `snapd-desktop-integration` snap trying to mirror our nix-set
  GTK theme (Breeze) into snap confinement; Breeze has no matching theme snap
  so its "install" action just fails. We don't use snaps for theming. Stop the
  running instance and mask the snapd-generated user service so it never starts
  again (a mask outranks snapd re-enabling it on refresh):
```sh
systemctl --user stop snap.snapd-desktop-integration.snapd-desktop-integration.service
systemctl --user mask snap.snapd-desktop-integration.snapd-desktop-integration.service
# (mask --now combines both: systemctl --user mask --now snap.snapd-desktop-integration.snapd-desktop-integration.service)
```

