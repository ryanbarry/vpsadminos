require 'osctld/dist_config/configurator'
require 'libosctl'

module OsCtld
  class DistConfig::Distributions::Base
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::SwitchUser

    def self.distribution(n = nil)
      if n
        DistConfig.register(n, self)
      else
        n
      end
    end

    attr_reader :ctrc, :ct, :distribution, :version

    # @param ctrc [Container::RunConfiguration]
    def initialize(ctrc)
      @ctrc = ctrc
      @ct = ctrc.ct
      @distribution = ctrc.distribution
      @version = ctrc.version
    end

    def configurator_class
      raise "define #{self.class}#configurator_class" unless self.class.const_defined?(:Configurator)

      cls = self.class::Configurator
      log(:debug, "Using #{cls} for #{ctrc.distribution}")
      cls
    end

    # Called before container start, can be used to e.g. add temporary mounts
    def pre_start(_opts = {})
      return unless volatile_is_systemd?
      # systemd by default does not monitor udev events in containers, which
      # means that there are no device units to depend on, e.g. for network
      # interfaces. systemd decides this by the  existence of socket
      # /run/udev/control and that /dev is devtmpfs. Our /dev cannot be
      # devtmpfs since that doesn't work in containers, and /run/udev/control
      # is created by a socket unit *after* systemd makes the decision to not
      # monitor udev events. After `systemctl daemon-reload`, it actually
      # starts to monitor udev events and the device units are created.
      #
      # See https://github.com/systemd/systemd/blob/729d2df8065ac90ac606e1fff91dc2d588b2795d/src/libsystemd/sd-device/device-monitor.c#L125
      #
      # We therefore mount /run as tmpfs before systemd is run and create
      # a stub for /run/udev/control, so that the check passes and udev events
      # are monitored from the start.
      #
      # /run has to be mounted by LXC from the container's user namespace, so
      # that it is owned by that user namespace. File /run/udev/control is
      # created later in {#post_mount}.

      # Check if /run isn't mounted already by user configuration
      return unless ct.mounts.detect { |mnt| %w[/run /run/].include?(mnt.mountpoint) }.nil?

      mem_limit = ct.find_memory_limit
      mnt_opts = %w[nosuid nodev mode=755 create=dir]
      mnt_opts << "size=#{mem_limit / 2}" if mem_limit

      ct.mounts.add(Mount::Entry.new(
                      'tmpfs',
                      '/run',
                      'tmpfs',
                      mnt_opts.join(','),
                      false,
                      temp: true,
                      in_config: true
                    ))
    end

    # Called by LXC post-mount hook on container start
    # @param opts [Hash]
    # @option opts [Integer] :ns_pid
    # @option opts [String] :rootfs_mount
    def post_mount(opts)
      return unless volatile_is_systemd?

      ContainerControl::Commands::WithMountns.run!(
        ct,
        ns_pid: opts[:ns_pid],
        chroot: opts[:rootfs_mount],
        block: proc do
          # /run is mounted by {#pre_start}
          FileUtils.mkdir_p('/run/udev')

          # Create /run/udev/control if it isn't already there
          begin
            File.stat('/run/udev/control')
          rescue Errno::ENOENT
            File.new('/run/udev/control', 'w').close
          end

          true
        end
      )
    end

    # Run just before the container is started
    def start(_opts = {})
      return unless ct.hostname || ct.dns_resolvers || ctrc.dist_configure_network?

      net_configured = with_rootfs do
        ret = false

        set_hostname if ct.hostname
        dns_resolvers if ct.dns_resolvers

        if ctrc.dist_configure_network?
          network
          ret = true
        end

        ret
      end

      ctrc.dist_network_configured = true if net_configured
    end

    # Gracefully stop the container
    # @param opts [Hash]
    # @option opts [:stop, :shutdown, :kill] :mode
    # @option opts [String] :message
    # @option opts [Integer] :timeout
    def stop(opts)
      ContainerControl::Commands::Stop.run!(
        ct,
        opts[:mode],
        message: opts[:message],
        timeout: opts[:timeout]
      )
    end

    # Set container hostname
    #
    # @param opts [Hash] options
    # @option opts [OsCtl::Lib::Hostname] :original previous hostname
    def set_hostname(opts = {})
      with_rootfs do
        configurator.set_hostname(ct.hostname, old_hostname: opts[:original])
        configurator.update_etc_hosts(ct.hostname, old_hostname: opts[:original])
      end

      apply_hostname if ct.running?
    end

    # Configure hostname in a running system
    def apply_hostname
      log(:warn, ct, "Unable to apply hostname on #{distribution}: not implemented")
    end

    # Update hostname in `/etc/hosts`, optionally removing configuration of old
    # hostname.
    #
    # @param opts [Hash] options
    # @option opts [OsCtl::Lib::Hostname, nil] :old_hostname
    def update_etc_hosts(opts = {})
      with_rootfs do
        configurator.update_etc_hosts(ct.hostname, old_hostname: opts[:old_hostname])
      end
    end

    # Remove the osctld-generated notice from /etc/hosts
    def unset_etc_hosts(_opts = {})
      with_rootfs do
        configurator.unset_etc_hosts
      end
    end

    def network(_opts = {})
      with_rootfs do
        configurator.network(ct.netifs)
      end
    end

    # Called when a new network interface is added to a container
    # @param opts [Hash]
    # @option opts [NetInterface::Base] :netif
    def add_netif(opts)
      with_rootfs do
        configurator.add_netif(ct.netifs, opts[:netif])
      end
    end

    # Called when a network interface is removed from a container
    # @param opts [Hash]
    # @option opts [NetInterface::Base] :netif
    def remove_netif(opts)
      with_rootfs do
        configurator.remove_netif(ct.netifs, opts[:netif])
      end
    end

    # Called when an existing network interface is renamed
    # @param opts [Hash]
    # @option opts [NetInterface::Base] :netif
    # @option opts [String] :original_name
    def rename_netif(opts)
      with_rootfs do
        configurator.rename_netif(ct.netifs, opts[:netif], opts[:original_name])
      end
    end

    def dns_resolvers(_opts = {})
      with_rootfs do
        configurator.dns_resolvers(ct.dns_resolvers)
      end
    end

    # @param opts [Hash] options
    # @option opts [String] user
    # @option opts [String] password
    def passwd(opts)
      ret = ct_syscmd(
        ct,
        %w[chpasswd],
        stdin: "#{opts[:user]}:#{opts[:password]}\n",
        run: true,
        valid_rcs: :all
      )

      return true if ret.success?

      log(:warn, ct, "Unable to set password: #{ret.output}")
    end

    # Return path to `/bin` or an alternative, where a shell is looked up
    # @return [String]
    def bin_path(_opts)
      '/bin'
    end

    def log_type
      ct.id
    end

    protected

    attr_reader :configurator

    def with_rootfs(&block)
      if @within_rootfs
        block.call
      else
        ContainerControl::Commands::WithRootfs.run!(
          ctrc.ct,
          ctrc:,
          block: proc do
            @configurator = configurator_class.new(
              ct.id,
              '/',
              ct.distribution,
              ct.version
            )
            @within_rootfs = true
            block.call
          end
        )
      end
    end

    # Check if the container is using systemd as init
    #
    # This method accesses the container's rootfs from the host, which is
    # dangerous because of symlinks and we really shouldn't be doing it... but
    # in this case, we only do readlink(), so it shouldn't do any harm.
    #
    # @return [Boolean]
    def volatile_is_systemd?
      return true if ctrc.distribution == 'nixos'

      begin
        File.readlink(File.join(ctrc.rootfs, 'sbin/init')).include?('systemd')
      rescue SystemCallError
        false
      end
    end
  end
end
