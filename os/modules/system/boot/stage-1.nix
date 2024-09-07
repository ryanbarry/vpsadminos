{ lib, utils, pkgs, config, options, ... }:
with lib;
let
  modulesTree = config.system.modulesTree;
  firmware = config.hardware.firmware;
  fileSystems = filter utils.fsNeededForBoot config.system.build.fileSystems;
  modules = pkgs.makeModulesClosure {
    rootModules = config.boot.initrd.availableKernelModules ++ config.boot.initrd.kernelModules;
    kernel = modulesTree;
    allowMissing = true;
    firmware = firmware;
  };
  dhcpcd = pkgs.dhcpcd.override { udev = null; };
  extraUtils = pkgs.runCommandCC "extra-utils"
  {
    buildInputs = [ pkgs.nukeReferences pkgs.lvm2 ];
    allowedReferences = [ "out" ];
  } ''
    set +o pipefail
    mkdir -p $out/bin $out/lib
    ln -s $out/bin $out/sbin

    copy_bin_and_libs() {
      [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
      cp -pd $1 $out/bin
    }

    # Copy Busybox
    for BIN in ${pkgs.busybox}/{s,}bin/*; do
      copy_bin_and_libs $BIN
    done

    # Copy modprobe
    copy_bin_and_libs ${pkgs.kmod}/bin/kmod
    ln -sf kmod $out/bin/modprobe

    # Copy dhcpcd
    copy_bin_and_libs ${pkgs.dhcpcd}/bin/dhcpcd

    # Copy dmsetup and lvm.
    copy_bin_and_libs ${getBin pkgs.lvm2}/bin/dmsetup
    copy_bin_and_libs ${getBin pkgs.lvm2}/bin/lvm

    # Copy eudev
    copy_bin_and_libs ${udev}/bin/udevd
    copy_bin_and_libs ${udev}/bin/udevadm
    for BIN in ${udev}/lib/udev/*_id; do
      copy_bin_and_libs $BIN
    done

    # Copy secrets if needed.
    ${optionalString (!config.boot.loader.supportsInitrdSecrets)
        (concatStringsSep "\n" (mapAttrsToList (dest: source:
           let source' = if source == null then dest else source; in
             ''
                mkdir -p $(dirname "$out/secrets/${dest}")
                cp -a ${source'} "$out/secrets/${dest}"
              ''
        ) config.boot.initrd.secrets))
     }

    ${config.boot.initrd.extraUtilsCommands}

    # Copy ld manually since it isn't detected correctly
    cp -pv ${pkgs.glibc.out}/lib/ld*.so.? $out/lib

    # Copy all of the needed libraries
    find $out/bin $out/lib -type f | while read BIN; do
      echo "Copying libs for executable $BIN"
      LDD="$(ldd $BIN)" || continue
      LIBS="$(echo "$LDD" | awk '{print $3}' | sed '/^$/d')"
      for LIB in $LIBS; do
        TGT="$out/lib/$(basename $LIB)"
        if [ ! -f "$TGT" ]; then
          SRC="$(readlink -e $LIB)"
          cp -pdv "$SRC" "$TGT"
        fi
      done
    done

    # Strip binaries further than normal.
    chmod -R u+w $out
    stripDirs "lib bin" "-s"

    # Run patchelf to make the programs refer to the copied libraries.
    find $out/bin $out/lib -type f | while read i; do
      if ! test -L $i; then
        nuke-refs -e $out $i
      fi
    done

    find $out/bin -type f | while read i; do
      if ! test -L $i; then
        echo "patching $i..."
        patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
      fi
    done

    # Make sure that the patchelf'ed binaries still work.
    echo "testing patched programs..."
    $out/bin/ash -c 'echo hello world' | grep "hello world"
    export LD_LIBRARY_PATH=$out/lib
    $out/bin/mount --help 2>&1 | grep -q "BusyBox"

    ${config.boot.initrd.extraUtilsCommandsTest}
  '';
  shell = "${extraUtils}/bin/ash";
  modprobeList = lib.concatStringsSep " " config.boot.initrd.kernelModules;
  dhcpHook = pkgs.writeScript "dhcpHook" ''
  #!${shell}
  '';

  udev = pkgs.eudev;
  udevRules = pkgs.runCommand "udev-rules"
    { allowedReferences = [ extraUtils ]; }
    ''
      mkdir -p $out

      echo 'ENV{LD_LIBRARY_PATH}="${extraUtils}/lib"' > $out/00-env.rules

      cp -v ${udev}/var/lib/udev/rules.d/60-cdrom_id.rules $out/
      cp -v ${udev}/var/lib/udev/rules.d/60-persistent-storage.rules $out/
      cp -v ${udev}/var/lib/udev/rules.d/80-drivers.rules $out/
      cp -v ${pkgs.lvm2}/lib/udev/rules.d/*.rules $out/

      for i in $out/*.rules; do
          substituteInPlace $i \
            --replace ata_id ${extraUtils}/bin/ata_id \
            --replace scsi_id ${extraUtils}/bin/scsi_id \
            --replace cdrom_id ${extraUtils}/bin/cdrom_id \
            --replace ${pkgs.util-linux}/sbin/blkid ${extraUtils}/bin/blkid \
            --replace /sbin/blkid ${extraUtils}/bin/blkid \
	    --replace ${getBin pkgs.lvm2}/bin/dmsetup /bin/dmsetup \
	    --replace ${getBin pkgs.lvm2}/bin/lvm /bin/lvm \
            --replace ${pkgs.lvm2}/bin ${extraUtils}/bin \
            --replace ${pkgs.lvm2}/bin ${extraUtils}/bin \
            --replace ${pkgs.bash}/bin/sh ${extraUtils}/bin/sh \
            --replace /usr/bin/readlink ${extraUtils}/bin/readlink \
            --replace /usr/bin/basename ${extraUtils}/bin/basename \
            --replace ${udev}/bin/udevadm ${extraUtils}/bin/udevadm
      done
    '';
  udevHwdb = config.environment.etc."udev/hwdb.bin".source;

  bootStage1 = pkgs.substituteAll {
    src = ./stage-1-init.sh;
    isExecutable = true;
    inherit shell modules modprobeList extraUtils dhcpHook udevRules udevHwdb;

    bootloader = config.system.boot.loader.id;
    fsInfo =
      let
        # busybox mount does not recognize x-initrd.mount option, which is added
        # by nixpkgs to mounts in initrd.
        fsOptions = fs: filter (opt: opt != "x-initrd.mount") fs.options;

        f = fs: [ fs.mountPoint (if fs.device != null then fs.device else "/dev/disk/by-label/${fs.label}") fs.fsType (builtins.concatStringsSep "," (fsOptions fs)) ];
      in pkgs.writeText "initrd-fsinfo" (concatStringsSep "\n" (concatMap f fileSystems));

    inherit (config.boot) predefinedFailAction;
    inherit (config.boot.initrd) preFailCommands preLVMCommands postDeviceCommands postMountCommands;
    inherit (config.system) storeOverlaySize;
  };

  initialRamdisk = pkgs.makeInitrd {
    compressor = "pigz";
    inherit (config.boot.initrd) prepend;

    contents = [
      {
        object = bootStage1;
        symlink = "/init";
      }

      {
        object = config.environment.etc."modprobe.d/nixos.conf".source;
        symlink = "/etc/modprobe.d/nixos.conf";
      }

      {
        object = pkgs.runCommand "initrd-kmod-blacklist-ubuntu" {
          src = "${pkgs.kmod-blacklist-ubuntu}/modprobe.conf";
          preferLocalBuild = true;
        } ''
          target=$out
          ${pkgs.buildPackages.perl}/bin/perl -0pe 's/## file: iwlwifi.conf(.+?)##/##/s;' $src > $out
        '';
        symlink = "/etc/modprobe.d/ubuntu.conf";
      }

      {
        object = pkgs.kmod-debian-aliases;
        symlink = "/etc/modprobe.d/debian.conf";
      }
    ];
  };

  initialRamdiskSecretAppender =
    let
      compressorExe = initialRamdisk.compressorExecutableFunction pkgs;
    in pkgs.writeScriptBin "append-initrd-secrets"
      ''
        #!${pkgs.bash}/bin/bash -e
        function usage {
          echo "USAGE: $0 INITRD_FILE" >&2
          echo "Appends this configuration's secrets to INITRD_FILE" >&2
        }

        if [ $# -ne 1 ]; then
          usage
          exit 1
        fi

        if [ "$1"x = "--helpx" ]; then
          usage
          exit 0
        fi

        ${lib.optionalString (config.boot.initrd.secrets == {})
            "exit 0"}

        export PATH=${pkgs.coreutils}/bin:${pkgs.libarchive}/bin:${pkgs.gzip}/bin:${pkgs.findutils}/bin

        function cleanup {
          if [ -n "$tmp" -a -d "$tmp" ]; then
            rm -fR "$tmp"
          fi
        }
        trap cleanup EXIT

        tmp=$(mktemp -d ''${TMPDIR:-/tmp}/initrd-secrets.XXXXXXXXXX)

        ${lib.concatStringsSep "\n" (mapAttrsToList (dest: source:
            let source' = if source == null then dest else toString source; in
              ''
                mkdir -p $(dirname "$tmp/.initrd-secrets/${dest}")
                cp -a ${source'} "$tmp/.initrd-secrets/${dest}"
              ''
          ) config.boot.initrd.secrets)
         }

        # mindepth 1 so that we don't change the mode of /
        (cd "$tmp" && find . -mindepth 1 | xargs touch -amt 197001010000 && find . -mindepth 1 -print0 | sort -z | bsdtar --uid 0 --gid 0 -cnf - -T - | bsdtar --null -cf - --format=newc @-) | \
          ${compressorExe} ${lib.escapeShellArgs initialRamdisk.compressorArgs} >> "$1"
      '';

in
{
  options = {
    boot.initrd.enable = mkOption {
      type = types.bool;
      default = !config.boot.isContainer;
      defaultText = "!config.boot.isContainer";
      description = ''
        Whether to enable the NixOS initial RAM disk (initrd). This may be
        needed to perform some initialisation tasks (like mounting
        network/encrypted file systems) before continuing the boot process.
      '';
    };
    boot.initrd.prepend = mkOption {
      default = [ ];
      type = types.listOf types.str;
      description = lib.mdDoc ''
        Other initrd files to prepend to the final initrd we are building.
      '';
    };
    boot.initrd.supportedFilesystems = mkOption {
      default = { };
      inherit (options.boot.supportedFilesystems) example type description;
    };
    boot.initrd.extraUtilsCommands = mkOption {
      internal = true;
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed in the builder of the
        extra-utils derivation.  This can be used to provide
        additional utilities in the initial ramdisk.
      '';
    };
    boot.initrd.extraUtilsCommandsTest = mkOption {
      internal = true;
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed in the builder of the
        extra-utils derivation after patchelf has done its
        job.  This can be used to test additional utilities
        copied in extraUtilsCommands.
      '';
    };
    boot.initrd.preFailCommands = mkOption {
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed before the failure prompt is shown.
      '';
    };
    boot.initrd.checkJournalingFS = mkOption {
      default = false;
      type = types.bool;
      readOnly = true;
      description = lib.mdDoc ''
        Whether to run {command}`fsck` on journaling filesystems such as ext3.
      '';
    };
    boot.initrd.preLVMCommands = mkOption {
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed immediately before LVM discovery.
        vpsAdminOS actually does not support LVM, this is just for compatibility
        with other modules.
      '';
    };
    boot.initrd.postDeviceCommands = mkOption {
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed immediately after stage 1 of the
        boot has loaded kernel modules and created device nodes in
        <filename>/dev</filename>.
      '';
    };
    boot.initrd.postMountCommands = mkOption {
      default = "";
      type = types.lines;
      description = ''
        Shell commands to be executed immediately after the stage 1
        filesystems have been mounted.
      '';
    };
    boot.initrd.secrets = mkOption {
      internal = true;
      default = {};
      type = types.attrsOf (types.nullOr types.path);
      description =
        ''
          Secrets to append to the initrd. The attribute name is the
          path the secret should have inside the initrd, the value
          is the path it should be copied from (or null for the same
          path inside and out).
        '';
      example = literalExpression
        ''
          { "/etc/dropbear/dropbear_rsa_host_key" =
              ./secret-dropbear-key;
          }
        '';
    };
    boot.loader.supportsInitrdSecrets = mkOption {
      internal = true;
      default = false;
      type = types.bool;
      description =
        ''
          Whether the bootloader setup runs append-initrd-secrets.
          If not, any needed secrets must be copied into the initrd
          and thus added to the store.
        '';
    };
    fileSystems = mkOption {
      type = with lib.types; loaOf (submodule {
        options.neededForBoot = mkOption {
          default = false;
          type = types.bool;
          description = ''
            If set, this file system will be mounted in the initial
            ramdisk.  By default, this applies to the root file system
            and to the file system containing
            <filename>/nix/store</filename>.
          '';
        };
      });
    };
  };
  config = {
    system.build = {
      inherit bootStage1 initialRamdisk initialRamdiskSecretAppender extraUtils;
    };
    boot.initrd.availableKernelModules = [ ];
    boot.initrd.kernelModules = [ "tun" "loop" "squashfs" "overlay" ];
  };
}
