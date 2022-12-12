let
  pkgs = import <nixpkgs> { overlays = (import ../os/overlays); };
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "libosctl";

  buildInputs = [
    pkgs.ruby
    pkgs.git
    pkgs.zlib
    pkgs.openssl
  ];

  shellHook = ''
    mkdir -p /tmp/dev-ruby-gems
    export GEM_HOME="/tmp/dev-ruby-gems"
    export GEM_PATH="$GEM_HOME:$PWD/lib"
    export PATH="$GEM_HOME/bin:$PATH"

    BUNDLE="$GEM_HOME/bin/bundle"

    [ ! -x "$BUNDLE" ] && ${pkgs.ruby}/bin/gem install bundler

    export BUNDLE_PATH="$GEM_HOME"
    export BUNDLE_GEMFILE="$PWD/Gemfile"

    $BUNDLE install

    export RUBYOPT=-rbundler/setup
  '';
}
