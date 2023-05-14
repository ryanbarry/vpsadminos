. "$IMAGEDIR/config.sh"
POINTVER=9.1
RELEASE=https://repo.almalinux.org/almalinux/${POINTVER}/BaseOS/x86_64/os/Packages/almalinux-release-${POINTVER}-1.9.el9.x86_64.rpm
BASEURL=https://repo.almalinux.org/almalinux/${POINTVER}/BaseOS/x86_64/os/

# CentOS 8 does not seem to have an updates repo, so this variable is used to
# add AppStream repository just for the installation process.
UPDATES=https://repo.almalinux.org/almalinux/${POINTVER}/AppStream/x86_64/os/

GROUPNAME='core'
EXTRAPKGS='almalinux-repos vim man'

. $INCLUDE/redhat-family.sh

bootstrap
configure-common
configure-redhat-common
configure-rhel-9
run-configure
set-initcmd "/sbin/init" "systemd.unified_cgroup_hierarchy=0"
