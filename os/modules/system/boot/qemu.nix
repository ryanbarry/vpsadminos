{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.boot.qemu;

  qemuDisk = {
    options = {
      device = mkOption {
        type = types.str;
        description = "Path to the disk device";
      };

      type = mkOption {
        type = types.enum [ "file" "blockdev" ];
        description = "Device type";
      };

      size = mkOption {
        type = types.str;
        default = "";
        description = "Device size";
      };

      create = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Create the device if it does not exist. Applicable only
          for file-backed devices.
        '';
      };
    };
  };

  allQemuParams =
    (flatten (imap0 (i: disk: [
      "-drive id=disk${toString i},file=${disk.device},if=none,format=raw"
      "-device ide-hd,drive=disk${toString i},bus=ahci.${toString i}"
    ]) cfg.disks))
    ++
    cfg.params;
in {
  options = {
    boot.qemu = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          QEMU runner
        '';
      };
      params = mkOption {
        internal = true;
        type = types.listOf types.str;
        description = "QEMU parameters";
      };

      memory = mkOption {
        internal = true;
        default = 8192;
        type = types.addCheck types.int (n: n > 256);
        description = "QEMU RAM in megabytes";
      };

      cpus = mkOption {
        internal = true;
        default = 1;
        type = types.addCheck types.int (n: n >= 1);
        description = "Number of available CPUs";
      };

      cpu.cores = mkOption {
        internal = true;
        default = 1;
        type = types.addCheck types.int (n: n >= 1);
        description = "Number of available CPU cores";
      };

      cpu.threads = mkOption {
        internal = true;
        default = 1;
        type = types.addCheck types.int (n: n >= 1);
        description = "Number of available threads";
      };

      cpu.sockets = mkOption {
        internal = true;
        default = 1;
        type = types.addCheck types.int (n: n >= 1);
        description = "Number of available CPU sockets";
      };

      disks = mkOption {
        type = types.listOf (types.submodule qemuDisk);
        default = [
          { device = "sda.img"; type = "file"; size = "8G"; create = true; }
        ];
        description = "Disks available within the VM";
      };
    };
  };

  config = mkIf cfg.enable {
    boot.kernelParams = [ "console=ttyS0" ];
    boot.qemu.params = lib.mkDefault [
      "-drive index=0,id=drive1,file=${config.system.build.squashfs},readonly=on,media=cdrom,format=raw,if=virtio"
      "-kernel ${config.system.build.kernel}/bzImage -initrd ${config.system.build.initialRamdisk}/initrd"
      ''-append "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams} quiet panic=-1"''
      "-nographic"
    ];

    system.build.runvm = pkgs.writeScript "runner" ''
      #!${pkgs.stdenv.shell}
      ${concatStringsSep "\n" (map (disk:
        ''[ ! -f "${disk.device}" ] && truncate -s${toString disk.size} "${disk.device}"''
      ) (filter (disk: disk.type == "file" && disk.create) cfg.disks))}
      exec ${pkgs.qemu_kvm}/bin/qemu-kvm -name vpsadminos -m ${toString cfg.memory} \
        -cpu host \
        -smp cpus=${toString cfg.cpus},cores=${toString cfg.cpu.cores},threads=${toString cfg.cpu.threads},sockets=${toString cfg.cpu.sockets} \
        -device ahci,id=ahci \
        -boot menu=on,splash-time=30 \
        -device virtio-net,netdev=net0 \
        -netdev user,id=net0,net=10.0.2.0/24,host=10.0.2.2,dns=10.0.2.3,hostfwd=tcp::2222-:22 \
        ${lib.concatStringsSep " \\\n  " allQemuParams}
    '';
  };
}
