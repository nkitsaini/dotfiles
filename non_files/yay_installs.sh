PACKAGES=(
    # Battery
    #   systemctl --user enable batsignal.service
    #   systemctl --user start batsignal.service
    batsignal
    tlp

    # Auto suggest command-not-found
    # pkgfile --update
    pkgfile


    alacritty
    android-file-transfer
    aria2
    base-devel
    bat
    batsignal
    bc
    bluez-utils
    brightnessctl
    bumblebee-status
    caddy
    chezmoi
    chromium
    dbeaver
    docker-compose
    dolphin
    dpkg
    dunst
    dust
    exa
    fd
    feh
    firefox
    git-delta
    github-cli
    gnome-terminal
    gnu-netcat
    gnumeric
    go
    gparted
    helixbinhx
    hexyl
    hplip
    htop
    httpie
    hwatch
    i3-wm
    i3blocks
    jq
    kopia-bin
    kubectl


    lshw B.02.19.2-6
    lssecret-git r10.20fd771-2
    man-db 2.11.2-1
    man-pages 6.05.01-1
    mold 2.1.0-1
    mosh 1.4.0-4
    mpv 1:0.36.0-1

    nano 7.2-1
    ncdu 2.3-1
    nethogs 0.8.7-1
    ngrok 3.3.4-1
    novnc 1.4.0-1
    nyxt 3.6.0-1

    obsidian 1.3.7-1
    p7zip 1:17.05-1

    pavucontrol 1:5.0+r64+geba9ca6-1
    perf 6.3-5

    postgresql 15.4-2
    powertop 2.15-1
    progress 0.16-1
    pyenv 1:2.3.25-1
    pypy3 7.3.12-1

    python-virtualenv 20.24.3-1
    qbittorrent 4.5.5-1

    rclone 1.63.1-1
    rsync 3.2.7-4

    # Screenshot
    scrot 1.10-1

    sd 0.7.6-2

    simplescreenrecorder 0.4.4-2

    # PDF Viewer
    sioyek 2.0.0-3

    sox 14.4.2+r182+g42b3557e-3

    starship 1.16.0-1
    sway 1:1.8.1-1

    tcpdump 4.99.4-1
    terminator 2.1.3-3

    thunar 4.18.7-1
    tig 2.5.8-1

    tldr 3.2.0-1

    # Terminal sharing
    tmate 2.4.0-3

    tmuxp 1.29.0-1
    tokei 12.1.2-1
    tree 2.1.1-1
    ttyd 1.7.3-1
    typst 1:0.7.0-1
    typst-lsp 0.9.5-1
    valgrind 3.21.0-4
    visual-studio-code-bin 1.81.1-1
    vlc 3.0.18-15
    vscode-langservers-extracted 4.7.0-1
    weston 12.0.2-1
    wireguard-tools 1.0.20210914-1
    xbindkeys 1.8.7-4
    xdotool 3.20211022.1-1
    xf86-video-amdgpu 23.0.0-1
    xf86-video-ati 1:22.0.0-1
    xf86-video-nouveau 1.0.17-2
    xf86-video-vmware 13.4.0-1
    xh 0.18.0-1
    yay 12.1.2-1
    zip 3.0-10
    zram-generator 1.1.2-1
)

echo "${PACKAGES[@]}"
# exec yay -Syy \
#    batsingal \
#    tlp \
