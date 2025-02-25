. "$IMAGEDIR/config.sh"
POINTVER=8.10
RELEASE=https://repo.almalinux.org/almalinux/${RELVER}/BaseOS/x86_64/os/Packages/almalinux-release-${POINTVER}-1.el8.x86_64.rpm
BASEURL=https://repo.almalinux.org/almalinux/${RELVER}/BaseOS/x86_64/os/

# CentOS 8 does not seem to have an updates repo, so this variable is used to
# add AppStream repository just for the installation process.
UPDATES=https://repo.almalinux.org/almalinux/${RELVER}/AppStream/x86_64/os/

GROUPNAME='core'
EXTRAPKGS='vim man'

. $INCLUDE/redhat-family.sh

bootstrap
configure-common
configure-redhat-common
configure-rhel-8
run-configure
