# Containers
Containers are created from images. Container image is a tarball with
configuration and data. Images can be automatically downloaded from remote
repositories, or they can be imported from local files.

Without any configuration, images will be downloaded from the *default*
repository. Our images are built using
[image-scripts](https://github.com/vpsfreecz/vpsadminos/tree/staging/image-scripts)
found in vpsAdminOS. Images built by these scripts are used in production
at [vpsFree.cz](https://vpsfree.org).

Let's create a container using an image from the
[default repository](https://images.vpsadminos.org):

```bash
osctl ct new --distribution ubuntu myct01
```

Available distributions from the default repository can be listed using *osctl*:

```bash
osctl repo image ls default
VENDOR       VARIANT   ARCH     DISTRIBUTION   VERSION               TAGS                                      CACHED
vpsadminos   minimal   x86_64   alpine         3.8                   -                                         -
vpsadminos   minimal   x86_64   alpine         3.9                   latest,stable                             -
vpsadminos   minimal   x86_64   arch           20190605              latest,stable                             -
vpsadminos   minimal   x86_64   centos         6                     -                                         -
vpsadminos   minimal   x86_64   centos         7                     latest,stable                             -
vpsadminos   minimal   x86_64   debian         8                     -                                         -
vpsadminos   minimal   x86_64   debian         9                     latest,stable                             -
vpsadminos   minimal   x86_64   devuan         2.0                   latest,stable                             -
vpsadminos   minimal   x86_64   fedora         29                    -                                         -
vpsadminos   minimal   x86_64   fedora         30                    latest,stable                             -
vpsadminos   minimal   x86_64   gentoo         20190605              latest,stable                             -
vpsadminos   minimal   x86_64   nixos          19.03                 latest,stable                             -
vpsadminos   minimal   x86_64   nixos          unstable-20190605     unstable                                  -
vpsadminos   minimal   x86_64   opensuse       leap-15.1             latest,stable                             -
vpsadminos   minimal   x86_64   opensuse       tumbleweed-20190605   -                                         -
vpsadminos   minimal   x86_64   slackware      14.2                  latest,stable                             -
vpsadminos   minimal   x86_64   ubuntu         16.04                 -                                         -
vpsadminos   minimal   x86_64   ubuntu         18.04                 latest,stable                             -
vpsadminos   minimal   x86_64   void           glibc-20190605        latest,latest-glibc,stable,stable-glibc   -
vpsadminos   minimal   x86_64   void           musl-20190605         latest-musl,stable-musl                   -
```
Let's see what files and directories define the created container:

```bash
ct assets myct01
TYPE        PATH                                                                     STATE     PURPOSE
dataset     tank/ct/myct01                                                           valid     Container's rootfs dataset
directory   /tank/ct/myct01/private                                                  valid     Container's rootfs
directory   /tank/hook/ct/myct01                                                     valid     User supplied script hooks
directory   /run/osctl/pools/tank/users/myct01/group.default/cts/myct01            valid     LXC configuration
file        /run/osctl/pools/tank/users/myct01/group.default/cts/myct01/config     valid     LXC base config
file        /run/osctl/pools/tank/users/myct01/group.default/cts/myct01/network    valid     LXC network config
file        /run/osctl/pools/tank/users/myct01/group.default/cts/myct01/cgparams   valid     LXC cgroup parameters
file        /run/osctl/pools/tank/users/myct01/group.default/cts/myct01/prlimits   valid     LXC resource limits
file        /run/osctl/pools/tank/users/myct01/group.default/cts/myct01/mounts     valid     LXC mounts
file        /run/osctl/pools/tank/users/myct01/group.default/cts/myct01/.bashrc    valid     Shell configuration file for osctl ct su
file        /tank/conf/ct/myct01.yml                                                 valid     Container config for osctld
file        /tank/log/ct/myct01.log                                                  valid     LXC log file
```

The container image is imported into a ZFS dataset that becomes the container's
rootfs. Then there is a standard LXC configuration, followed by a config for
*osctld*. The container's existence is defined by that config. And the last entry
is the log file, where you can find errors if the container cannot be started.

To start the container, use:

```bash
osctl ct start -F myct01
```

Option `-F`, `--foreground` attaches the container's console before starting it,
so you can see the boot process and then login. Of course, the root's password
is not set yet. The console can be detached by pressing `Ctrl-a q`.

To set the password, you can use `osctl ct passwd`:

```bash
osctl ct passwd myct01 root secret
```

The command above will set root's password to `secret`. If you don't provide
the password as an argument, `osctl` will ask you for it on standard input.
You can then reopen the console and login:

```bash
osctl ct console myct01
```

The container's shell can be attached even without knowing any password with
`osctl ct attach`:

```bash
osctl ct attach myct01
```

The shell can be closed using `exit` or `Ctrl-d`.

Arbitrary commands can be executed using `osctl ct exec`:

```bash
osctl ct exec myct01 <command...>
```

You can view container states using by listing all containers:

```bash
osctl ct ls
POOL   ID       USER     GROUP      DISTRIBUTION   VERSION   STATE     INIT_PID   MEMORY   CPU_TIME 
tank   myct01   myct01   /default   ubuntu         16.04     running   7894       36.0M    1s
```

Or just one specific container, showing all container parameters:

```bash
osctl ct show myct01
          POOL:  tank
            ID:  myct01
          USER:  myct01
         GROUP:  /default
       DATASET:  tank/ct/myct01
        ROOTFS:  /tank/ct/myct01/private
      LXC_PATH:  /run/osctl/pools/tank/users/myct01/group.default/cts
       LXC_DIR:  /run/osctl/pools/tank/users/myct01/group.default/cts/myct01
    GROUP_PATH:  osctl/pool.tank/group.default/user.myct01/ct.myct01/user-owned
  DISTRIBUTION:  ubuntu
       VERSION:  16.04
         STATE:  running
      INIT_PID:  7894
      HOSTNAME:  -
 DNS_RESOLVERS:  -
       NESTING:  -
        MEMORY:  36.0M
       KMEMORY:  3.0M
      CPU_TIME:  1s
 CPU_USER_TIME:  1s
  CPU_SYS_TIME:  0s
```

As you can see from the list above, *osctld* can also manage the container's
hostname and DNS resolvers. Hostname defaults to the container *id* and you
can manually change the hostname from within the container. If you wish to have
the hostname managed by *osctld* from the host, you can set it as:

```
osctl ct set hostname myct01 your-hostname
```

*osctld* will then configure the hostname on every container start, including
configs within the containers. Should you ever want to prevent that, you can
unset the hostname:

```
osctl ct unset hostname myct01
```

Similarly to hostname, you can configure DNS resolvers, which are written to
`/etc/resolv.conf` on every start:

```
osctl ct set dns-resolver myct01 8.8.8.8 8.8.4.4
osctl ct unset dns-resolver myct01
```

To allow LXC nesting, i.e. creating LXC containers inside the containers, you
have to enable it:

```
osctl ct set nesting myct01
```

Continue by reading more about container [networking](networking.md),
[resource management](resources.md) and [mounts](mounts.md).
