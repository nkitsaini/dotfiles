{pkgs, ...}: {
  hardware.firmware = [
  
      pkgs. linux-firmware # has rtl_bt/rtl8822cu_fw.bin bluetooth driver
  ];
}
