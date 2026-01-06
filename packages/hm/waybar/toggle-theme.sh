#!/bin/bash

# scripts/toggle-theme.sh

SIGNAL_NUM=8

# FIX: Use ${1:-} to handle the empty variable safely
if [ "${1:-}" == "toggle" ]; then

    current=$(gsettings get org.gnome.desktop.interface color-scheme)

    if [ "$current" == "'prefer-dark'" ]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    else
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    fi

    pkill -RTMIN+${SIGNAL_NUM} waybar
    exit 0
fi

# -- Status Check --
current=$(gsettings get org.gnome.desktop.interface color-scheme)

if [ "$current" == "'prefer-dark'" ]; then
    echo '{"text": "", "tooltip": "Dark Mode", "class": "dark"}'
else
    echo '{"text": "", "tooltip": "Light Mode", "class": "light"}'
fi
