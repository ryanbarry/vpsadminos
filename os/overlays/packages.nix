self: super:
{
  bird = super.bird.overrideAttrs (oldAttrs: rec {
    patches = super.bird.patches ++
      [ ../packages/bird/disable-kif-warnings-osrtr0.patch ];
    });

  devcgprog = super.callPackage ../packages/devcgprog {};

  htop = super.htop.overrideAttrs (oldAttrs: rec {
    src = super.fetchFromGitHub {
      owner = "vpsfreecz";
      repo = "htop";
      rev = "251a450a9d52e221aeefbc85a43e0c47327774f2";
      sha256 = "sha256:1l9srlwbn5hqww9in5whbfx7rb28mqmh267fj4km68qvz38469vk";
    };

    nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
      super.autoreconfHook
    ];

    preConfigure = ''
      sh autogen.sh
    '';

    configureFlags = [
      "--enable-vpsadminos"
    ];
  });

  irq_heatmap = super.callPackage ../packages/irq_heatmap {};

  lxc =
    let
      libcap = super.libcap.overrideAttrs (oldAttrs: rec {
        postInstall = builtins.replaceStrings [ ''rm "$lib"/lib/*.a'' ] [ "" ]
                                              oldAttrs.postInstall;
      });
    in super.callPackage ../packages/lxc/default.nix {
      inherit libcap;
      systemd = null;
    };

  lxcfs = super.lxcfs.overrideAttrs (oldAttrs: rec {
    version = "4.0.11";

    src = super.fetchFromGitHub {
      owner = "vpsfreecz";
      repo = "lxcfs";
      rev = "f3ac5f4828475bfa925e3d455dea5be6a4eaf40c";
      sha256 = "sha256-0jYnofZPq7/uwOMQkjgFIHmkCm92o+D1b4J18fSp31c=";
    };

    postFixup = ''
      # liblxcfs.so is reloaded with dlopen()
      patchelf --set-rpath "/run/current-system/sw/lib/lxcfs:$(patchelf --print-rpath "$out/bin/lxcfs"):$out/lib" "$out/bin/lxcfs"
    '';
  });

  mbuffer = super.mbuffer.overrideAttrs (oldAttrs: rec {
    version = "20211018";

    doCheck = false;

    src = super.fetchurl {
      url = "http://www.maier-komor.de/software/mbuffer/mbuffer-${version}.tgz";
      sha256 = "sha256:1qxnbpyly00kml3sjan9iqg6pqacsi3yqq66x25w455cwkjc2h72";
    };

    nativeBuildInputs = [ super.which ];
  });

  runit = super.runit.overrideAttrs (oldAttrs: rec {
    patches = [
      ../packages/runit/kexec-support.patch
      ../packages/runit/maxservices-100k.patch
    ];
  });

  scrubctl = super.callPackage ../packages/scrubctl {};

  vdevlog = super.callPackage ../packages/vdevlog {};
}
