{ configs, pkgs, lib, ... }:

{
  imports = lib.optionals
    (lib.pathExists ./local.nix)
    (builtins.trace "Using os/configs/local.nix" [ ./local.nix ]);

  boot.kernelParams = [ "root=/dev/vda" ];
  boot.initrd.kernelModules = [ "virtio" "virtio_pci" "virtio_net" "virtio_rng" "virtio_blk" "virtio_console" ];

  networking.hostId = lib.mkDefault "f3276671";
  networking.hostName = lib.mkDefault "vpsadminos";
  networking.static.enable = lib.mkDefault true;
  networking.lxcbr.enable = true;
  networking.nameservers = [ "10.0.2.3" ];

  boot.qemu.enable = true;
  boot.qemu.disks = lib.mkDefault [
    { device = "sda.img"; type = "file"; size = "8G"; create = true; }
  ];

  boot.zfs.pools = lib.mkDefault {
    tank = {
      layout = [
        { devices = [ "sda" ]; }
      ];
      doCreate = true;
      install = true;
    };
  };

  tty.autologin.enable = true;
  services.haveged.enable = true;
  os.channel-registration.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    git
  ];

  users.motd = ''

    Welcome to vpsAdminOS

    Configure osctld:
      osctl pool install tank

    Create a container:
      osctl ct new --distribution alpine myct01

    Configure container networking:
      osctl ct netif new routed myct01 eth0
      osctl ct netif ip add myct01 eth0 1.2.3.4/32

    Start the container:
      osctl ct start myct01

    More information:
      man osctl
    '';
}
