{
  disko.devices = {
    disk = {
      vdb = {
        type = "disk";
        device = "/dev/vdb";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "boot";
              name = "ESP";
              priority = 1;
              size="512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              label = "swap";
              size = "10G";
              content = {
                type = "swap";
                resumeDevice = true; # resume from hiberation from this device
              };
            };
            # swap = {
            #   label = "boot";
            #   name = "ESP";
            #   priority = 1;
            #   size="512M";
            #   type = "EF00";
            #   content = {
            #     type = "filesystem";
            #     format = "vfat";
            #     mountpoint = "/boot";
            #   };
            # };
            root = {
              label = "nixos";
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Override existing partition
                # Subvolumes must set a mountpoint in order to be mounted,
                # unless their parent is mounted
                subvolumes = {
                  # Subvolume name is different from mountpoint
                  "/rootfs" = {
                    mountOptions = [ "compress=zstd:1" "noatime" ];
                    mountpoint = "/";
                  };
                  # Subvolume name is the same as the mountpoint
                  "/home" = {
                    mountOptions = [ "compress=zstd:1" "noatime" ];
                    mountpoint = "/home";
                  };
                  # Parent is not mounted so the mountpoint must be set
                  "/nix" = {
                    mountOptions = [ "compress=zstd:1" "noatime" ];
                    mountpoint = "/nix";
                  };
                };

                # What the heck is this?
                mountpoint = "/partition-root";
              };
            };
          };
        };
      };
    };
  };
}
