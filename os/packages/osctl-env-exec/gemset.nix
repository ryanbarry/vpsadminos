{
  binman = {
    dependencies = ["opener"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1wn4myh5ir80j6xmvrbz6hrq47m9p4l6yd6nyk1g1r9klds52yvn";
      type = "gem";
    };
    version = "5.1.0";
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
  highline = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0yclf57n2j3cw8144ania99h1zinf8q3f5zrhqa754j6gl95rp9d";
      type = "gem";
    };
    version = "2.0.3";
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
      sha256 = "0nalhin1gda4v8ybk6lq8f407cgfrj6qzn234yra4ipkmlbfmal6";
      type = "gem";
    };
    version = "2.6.3";
  };
  md2man = {
    dependencies = ["binman" "redcarpet" "rouge"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0ii25vxasg3fm93wa2cabl4c8ijqdcdr8if8sd98rv9kix42gpp5";
      type = "gem";
    };
    version = "5.1.2";
  };
  opener = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0ngxijhmcfjv23cp3r0lmnrhya37w8p16bandcw28z59ib4crrbz";
      type = "gem";
    };
    version = "0.1.0";
  };
  osctl-env-exec = {
    dependencies = ["gli" "highline" "ipaddress" "json" "md2man" "rake" "rake-compiler" "ruby-progressbar" "yard"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "18cfyq2p9g8s7ajmw2klfmjrhvl717aa7akb6vpf7sjkrwlfbk37";
      type = "gem";
    };
    version = "22.11.0.build20230410220547";
  };
  rake = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "15whn7p9nrkxangbs9hh75q585yfn66lv0v2mhj6q6dl6x8bzr2w";
      type = "gem";
    };
    version = "13.0.6";
  };
  rake-compiler = {
    dependencies = ["rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "03xcg72wrpxg14k0l1gqbi9wdzzaknswcbb8n11abrf7i65l4bvm";
      type = "gem";
    };
    version = "1.2.1";
  };
  redcarpet = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1sg9sbf9pm91l7lac7fs4silabyn0vflxwaa2x3lrzsm0ff8ilca";
      type = "gem";
    };
    version = "3.6.0";
  };
  rouge = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1dnfkrk8xx2m8r3r9m2p5xcq57viznyc09k7r3i4jbm758i57lx3";
      type = "gem";
    };
    version = "3.30.0";
  };
  ruby-progressbar = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "02nmaw7yx9kl7rbaan5pl8x5nn0y4j5954mzrkzi9i3dhsrps4nc";
      type = "gem";
    };
    version = "1.11.0";
  };
  yard = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "17bwa0lcxhfmxd5dahnw70xzahmdm3q1x7g5qjdpn4x8f7ij9164";
      type = "gem";
    };
    version = "0.9.32";
  };
}
