{ pkgs, ... }: {
  hardware.firmware = [
    pkgs.linux-firmware # has rtl_bt/rtl8822cu_fw.bin bluetooth driver
  ];
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot =
    true; # powers up the default Bluetooth controller on boot
  hardware.bluetooth.settings = {
    General = {
      FastConnectable = true;
    };
  };
  services.blueman.enable = false; # Disabled as it enables auto-connect for some reason
}
