# Gets installed in both os deps and hm deps
# NOTE: You cannot include packages that are defined using home-manager modules
# here (like tmux, git), for them only include them in nixos configuration
pkgs: with pkgs; [
  binutils
  coreutils-full
  curl
  dnsutils
  dosfstools
  fd
  devenv
  htop
  powertop
  iputils
  jq
  # moreutils
  nmap
  sd
  util-linux # has cfdisk
  whois
  gparted
]
