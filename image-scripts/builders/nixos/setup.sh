cat <<EOF > /etc/nixos/configuration.nix
{ config, pkgs, ... }:
{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
    ./vpsadminos.nix
  ];

  environment.systemPackages = with pkgs; [
    git
    gnumake
  ];

  time.timeZone = "Europe/Amsterdam";
  system.stateVersion = "21.05";
}
EOF

# Set NIX_PATH and other stuff
. /etc/profile

# Configure the system
nixos-rebuild switch
