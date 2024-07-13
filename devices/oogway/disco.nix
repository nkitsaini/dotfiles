# TODO: Next time, turn this into real nixos module, as mentioned in: https://github.com/nix-community/disko/blob/master/docs/quickstart.md (just modify for flakes)
# That will bring down the installations to a fix number of steps along with building a tailored ISO.
# - Get keys from password manager (keep bitwarden in image)
# - Setup ssh authorized_keys from github (keep a binary to do this, actually make it do everything, or print all steps)
# - clone the git repo (have git, tmux stuff in image)
# - run this file to create partitions (have disko pre-installed in image)
# - run `nixos-generate-config --show-hardware-config --no-filesystems` and save to this directory  (also remove the hardware-configuration from here, so that it is an error, or do something like {todo.add-hardware-config = ''This will fail. Run command to generate config''}})
# - run `nixos-install --flake ...`
# Maybe also have helix in the iso to avoid rebuilding (this is the only thing we build from source). Hopefully no more, once plugin system arrives.
#     - similarly see if any big dependency can be included to allow quick install.

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
              size = "10G";
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
              };
            };
          };
        };
      };
    };
  };
}
