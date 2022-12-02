{ config, pkgs, lib, ... }:
{
  services.osctl.image-repository.vpsadminos = {
    rebuildAll = true;

    vendors.vpsadminos = { defaultVariant = "minimal"; };
    defaultVendor = "vpsadminos";

    images = {
      almalinux = {
        "8" = {};
        "9" = { tags = [ "latest" "stable" ]; };
      };

      alpine = {
        "3.14" = {};
        "3.15" = {};
        "3.16" = {};
        "3.17" = { tags = [ "latest" "stable" ]; };
      };

      arch.rolling = { name = "arch"; tags = [ "latest" "stable" ]; };

      centos = {
        "7" = {};
        "8-stream" = { tags = [ "latest-8-stream" "latest" "stable" ]; };
        "9-stream" = { tags = [ "latest-9-stream" "latest-stream" ]; };
      };

      debian = {
        "9" = {};
        "10" = {};
        "11" = { tags = [ "latest" "stable" ]; };
        "testing" = { tags = [ "testing" ]; };
        "unstable" = { tags = [ "unstable" ]; };
      };

      devuan = {
        "3.0" = {};
        "4" = { tags = [ "latest" "stable" ]; };
      };

      fedora = {
        "36" = {};
        "37" = { tags = [ "latest" "stable" ]; };
      };

      gentoo = {
        openrc = { tags = [ "latest" "stable" "latest-openrc" "stable-openrc" ]; };
        systemd = { tags = [ "latest-systemd" "stable-systemd" ]; };
        musl = { tags = [ "latest-musl" "stable-musl" ]; };
      };

      nixos = {
        "22.11" = { tags = [ "latest" "stable" ]; };
        "unstable" = { tags = [ "unstable" ]; };
      };

      opensuse = {
        "leap-15.3" = {};
        "leap-15.4" = { tags = [ "latest" "stable" ]; };
        "tumbleweed" = { tags = [ "latest-tumbleweed" ]; };
      };

      rocky = {
        "8" = {};
        "9" = { tags = [ "latest" "stable" ]; };
      };

      slackware = {
        "15.0" = { tags = [ "latest" "stable" ]; };
        "current" = { tags = [ "latest-current" ]; };
      };

      ubuntu = {
        "18.04" = {};
        "20.04" = {};
        "22.04" = { tags = [ "latest" "stable" ]; };
      };

      void = {
        "glibc" = { tags = [ "latest" "stable" "latest-glibc" "stable-glibc" ]; };
        "musl" = { tags = [ "latest-musl" "stable-musl" ]; };
      };
    };

    garbageCollection = [
      {
        distribution = "arch";
        version = "\\d+";
        keep = 4;
      }
      {
        distribution = "centos";
        version = "8-stream-\\d+";
        keep = 4;
      }
      {
        distribution = "centos";
        version = "9-stream-\\d+";
        keep = 4;
      }
      {
        distribution = "debian";
        version = "testing-\\d+";
        keep = 4;
      }
      {
        distribution = "debian";
        version = "unstable-\\d+";
        keep = 4;
      }
      {
        distribution = "gentoo";
        version = "openrc-\\d+";
        keep = 4;
      }
      {
        distribution = "gentoo";
        version = "systemd-\\d+";
        keep = 4;
      }
      {
        distribution = "gentoo";
        version = "musl-\\d+";
        keep = 4;
      }
      {
        distribution = "nixos";
        version = "unstable-\\d+";
        keep = 4;
      }
      {
        distribution = "opensuse";
        version = "tumbleweed-\\d+";
        keep = 4;
      }
      {
        distribution = "slackware";
        version = "current-\\d+";
        keep = 4;
      }
      {
        distribution = "void";
        version = "glibc-\\d+";
        keep = 4;
      }
      {
        distribution = "void";
        version = "musl-\\d+";
        keep = 4;
      }
    ];
  };
}
