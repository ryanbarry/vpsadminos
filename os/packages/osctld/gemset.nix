{
  concurrent-ruby = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0nwad3211p7yv9sda31jmbyw6sdafzmdi2i2niaz6f0wk5nq9h0f";
      type = "gem";
    };
    version = "1.1.9";
  };
  filelock = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "085vrb6wf243iqqnrrccwhjd4chphfdsybkvjbapa2ipfj1ja1sj";
      type = "gem";
    };
    version = "1.1.1";
  };
  gli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1sxpixpkbwi0g1lp9nv08hb4hw9g563zwxqfxd3nqp9c1ymcv5h3";
      type = "gem";
    };
    version = "2.20.1";
  };
  ipaddress = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1x86s0s11w202j6ka40jbmywkrx8fhq8xiy8mwvnkhllj57hqr45";
      type = "gem";
    };
    version = "0.8.3";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1z9grvjyfz16ag55hg522d3q4dh07hf391sf9s96npc0vfi85xkz";
      type = "gem";
    };
    version = "2.6.1";
  };
  libosctl = {
    dependencies = ["rainbow" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0wx5lc1vyrbjh28f6rka8ni2qz3pyggnardy6q6dx12xh80m50md";
      type = "gem";
    };
    version = "21.11.0.build20220305130230";
  };
  netlinkrb = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0lhy9jdvwa9ywj63a7cvmiqx3nxccl7vllsawwmqrwaqgxnqc5ii";
      type = "gem";
    };
    version = "0.18.vpsadminos.0";
  };
  osctl-repo = {
    dependencies = ["filelock" "gli" "json" "libosctl" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1c7fgkgljg2j75vwnykbky3mvpm8wmysd3vb6hnlcwr9r4z1bx50";
      type = "gem";
    };
    version = "21.11.0.build20220305130230";
  };
  osctld = {
    dependencies = ["concurrent-ruby" "ipaddress" "json" "libosctl" "netlinkrb" "osctl-repo" "osup" "require_all" "ruby-lxc"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0na52zbiimjrn3riis35fgfkvrdvifmikhkdq2gvsg04id5bfh02";
      type = "gem";
    };
    version = "21.11.0.build20220305130230";
  };
  osup = {
    dependencies = ["gli" "json" "libosctl" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "139msjh6hyi5sd9ifzbbb4qbp19vry5yp0c8821fg75wvspcrgiv";
      type = "gem";
    };
    version = "21.11.0.build20220305130230";
  };
  rainbow = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0smwg4mii0fm38pyb5fddbmrdpifwv22zv3d3px2xx497am93503";
      type = "gem";
    };
    version = "3.1.1";
  };
  require_all = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0sjf2vigdg4wq7z0xlw14zyhcz4992s05wgr2s58kjgin12bkmv8";
      type = "gem";
    };
    version = "2.0.0";
  };
  ruby-lxc = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1p5zgv5fwdgfrhh7sc8mlcck0ckv73yza9yf1hb1j6q1637xqvv0";
      type = "gem";
    };
    version = "1.2.4.vpsadminos.3";
  };
}
