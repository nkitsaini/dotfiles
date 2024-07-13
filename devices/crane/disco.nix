# NOTE: if after the install /boot gets garbled, i.e. ls /boot gives Input/Output error with weird filenames, clean and re-format /boot and run
# sudo NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
# This happened once, not sure if it was one time thing or not?
{
  disko.devices.disk = {
    primary = {
      type = "disk";
      # Next time use ID
      device = "/dev/sda";
      content = {
        type = "gpt";

        partitions = {
          boot = {
            size = "512M";
            type = "EF02";
            priority = 1;
          };
          swap = {
            label = "swap";
            size = "5G";
            content = {
              type = "swap";
              resumeDevice = true; # resume from hiberation from this device
            };
          };
          root = {
            label = "nixos";
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ]; # Override existing partition
              # Subvolumes must set a mountpoint in order to be mounted,
              # unless their parent is mounted
              subvolumes = {
                "/rootfs" = {
                  mountOptions = [ "compress=zstd:1" "noatime" ];
                  mountpoint = "/";
                };
                "/home" = {
                  mountOptions = [ "compress=zstd:1" "noatime" ];
                  mountpoint = "/home";
                };
                "/nix" = {
                  mountOptions = [ "compress=zstd:1" "noatime" ];
                  mountpoint = "/nix";
                };
              };
            };
          };
        };
      };
    };
  };
}
