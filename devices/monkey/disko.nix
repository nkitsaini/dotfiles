# IDS
# nvme-nvme.1c5c-414e31324e343139303130343032423151-534b48796e69785f48465330303154444539583038314e-00000001@        nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q_1@
# nvme-nvme.1c5c-414e31324e343139303130343032423151-534b48796e69785f48465330303154444539583038314e-00000001-part1@  nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q_1-part1@
# nvme-nvme.1c5c-414e31324e343139303130343032423151-534b48796e69785f48465330303154444539583038314e-00000001-part2@  nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q_1-part2@
# nvme-nvme.1c5c-414e31324e343139303130343032423151-534b48796e69785f48465330303154444539583038314e-00000001-part3@  nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q_1-part3@
# nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q@                                                                   usb-Kingston_DataTraveler_2.0_60A44C413C91F040961B3D3C-0:0@
# nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q-part1@                                                             usb-Kingston_DataTraveler_2.0_60A44C413C91F040961B3D3C-0:0-part1@
# nvme-SKHynix_HFS001TDE9X081N_AN12N419010402B1Q-part2@                                                             usb-Kingston_DataTraveler_2.0_60A44C413C91F040961B3D3C-0:0-part2@

{
  disko.devices.disk = {
    primary = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "boot";
            name = "ESP";
            priority = 1;
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          swap = {
            label = "swap";
            size = "42G";
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
