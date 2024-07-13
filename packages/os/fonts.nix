{ pkgs, ... }: {
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-monochrome-emoji
    (nerdfonts.override { fonts = [ "Noto" ]; })
    font-awesome
  ];
}
