{
  services.udev.enable = true;

  # From: https://forum.xfce.org/viewtopic.php?pid=66392#p66392 (but using ntfs-3g instead of kernel ntfs3)
  services.udev.extraRules = ''
    SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="ntfs", ENV{ID_FS_TYPE}="ntfs-3g" , ENV{UDISKS_FILESYSTEM_SHARED}="0"
  '';
}
