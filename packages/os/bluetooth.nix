{ pkgs, ... }: {
  hardware.firmware = [
    pkgs.linux-firmware # has rtl_bt/rtl8822cu_fw.bin bluetooth driver
  ];
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  # BlueZ 5.86 regression: a2dp_source connects before a2dp_sink for dual-role
  # devices (e.g. Amazon Echo, many speakers), so the PC is misclassified as the
  # speaker and audio flows device -> PC instead of PC -> device. Cherry-pick the
  # upstream fix (066a164, "a2dp: connect source profile after sink").
  #
  # Scoped to the bluetoothd package only (not a global `bluez` overlay) so we don't
  # invalidate the binary cache for everything that links libbluetooth (vlc, chromium,
  # gstreamer, ...). Remove once bluez >= 5.87 (or nixpkgs backports the fix).
  hardware.bluetooth.package = pkgs.bluez.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./bluez-a2dp-connect-source-after-sink.patch
    ];
  });
  hardware.bluetooth.powerOnBoot =
    true; # powers up the default Bluetooth controller on boot
  hardware.bluetooth.settings = {
    General = {
      FastConnectable = true;
    };
  };
  services.blueman.enable = false; # Disabled as it enables auto-connect for some reason
}
