require 'libosctl'
require 'osctld/lockable'
require 'osctld/manipulable'
require 'osctld/assets/definition'

module OsCtld
  class Container
    include Lockable
    include Manipulable
    include Assets::Definition
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::SwitchUser

    def self.default_dataset(pool, id, dataset_cache: nil)
      name = File.join(pool.ct_ds, id)
      OsCtl::Lib::Zfs::Dataset.new(name, base: name, cache: dataset_cache)
    end

    attr_inclusive_reader :pool, :id, :user, :dataset, :group, :distribution,
      :version, :arch, :autostart, :ephemeral, :hostname, :dns_resolvers,
      :nesting, :prlimits, :mounts, :send_log, :netifs, :cgparams,
      :devices, :seccomp_profile, :apparmor, :attrs, :state, :lxc_config,
      :init_cmd, :start_menu, :raw_configs, :run_conf

    alias_method :ephemeral?, :ephemeral

    # @param pool [Pool]
    # @param id [String]
    # @param user [User, nil]
    # @param group [Group, nil]
    # @param dataset [String, nil]
    # @param opts [Hash] options
    # @option opts [Boolean] load load config
    # @option opts [String] load_from load from this string instead of config file
    # @option opts [Boolean] staged create a staged container
    # @option opts [Boolean] devices determines whether devices are initialized
    # @option opts [OsCtl::Lib::Zfs::DatasetCache] dataset_cache
    def initialize(pool, id, user = nil, group = nil, dataset = nil, opts = {})
      init_lock
      init_manipulable

      opts[:load] = true unless opts.has_key?(:load)

      @pool = pool
      @id = id
      @user = user
      @group = group
      @dataset = dataset
      @state = opts[:staged] ? :staged : :unknown
      @ephemeral = false
      @netifs = NetInterface::Manager.new(self)
      @cgparams = nil
      @devices = nil
      @prlimits = nil
      @mounts = nil
      @hostname = nil
      @dns_resolvers = nil
      @nesting = false
      @seccomp_profile = nil
      @apparmor = AppArmor.new(self)
      @lxc_config = Container::LxcConfig.new(self)
      @init_cmd = nil
      @raw_configs = Container::RawConfigs.new
      @attrs = Attributes.new
      @run_conf = nil

      if opts[:load]
        load_opts = {
          init_devices: !opts.has_key?(:devices) || opts[:devices],
          dataset_cache: opts[:dataset_cache],
        }

        if opts[:load_from]
          load_config_string(opts[:load_from], **load_opts)
        else
          load_config_file(config_path, **load_opts)
        end
      end
    end

    def ident
      inclusively { "#{pool.name}:#{id}" }
    end

    def configure(distribution, version, arch)
      exclusively do
        @distribution = distribution
        @version = version
        @arch = arch
        @netifs = NetInterface::Manager.new(self)
        @nesting = false
        @seccomp_profile = default_seccomp_profile
        @cgparams = CGroup::ContainerParams.new(self)
        @devices = Devices::ContainerManager.new(self)
        @prlimits = PrLimits::Manager.default(self)
        @mounts = Mount::Manager.new(self)
        @run_conf ||= new_run_conf
        devices.init
        save_config
      end
    end

    def assets
      define_assets do |add|
        # Datasets
        add.dataset(
          dataset.to_s,
          desc: "Container's rootfs dataset",
          uidmap: uid_map.map(&:to_a),
          gidmap: gid_map.map(&:to_a),
          user: root_host_uid,
          group: root_host_gid,
          mode: 0770,
          validate_if: mounted?,
        )

        # Directories and files
        add.directory(
          rootfs,
          desc: "Container's rootfs",
          user: root_host_uid,
          group: root_host_gid,
          mode_bit_and: 0111, # has all executable bits set
          validate_if: mounted?,
        )

        add.directory(
          user_hook_script_dir,
          desc: 'User supplied script hooks',
          user: 0,
          group: 0,
          mode: 0700
        )
        add.directory(
          lxc_dir,
          desc: 'LXC configuration',
          user: 0,
          group: user.ugid,
          mode: 0750
        )

        lxc_config.assets(add)

        add.file(
          File.join(lxc_dir, '.bashrc'),
          desc: 'Shell configuration file for osctl ct su',
          user: 0,
          group: 0,
          mode: 0644
        )

        add.file(
          config_path,
          desc: 'Container config for osctld',
          user: 0,
          group: 0,
          mode: 0400
        )
        add.file(
          log_path,
          desc: 'LXC log file',
          user: 0,
          group: user.ugid,
          mode: 0660
        )

        run_conf.assets(add) if run_conf
      end
    end

    # Duplicate the container with a different ID
    #
    # The returned container has `state` set to `:staged` and its assets will
    # not exist, so the caller has to build the container and call
    # `ct.state = :complete` for the container to become usable.
    #
    # @param id [String] new container id
    # @param opts [Hash] options
    # @option opts [Pool] :pool target pool, optional
    # @option opts [User] :user target user, optional
    # @option opts [Group] :group target group, optional
    # @option opts [String] :dataset target dataset, optional
    def dup(id, opts = {})
      ct = clone
      ct.send(:clone_from, self, id, opts)
      ct
    end

    # @return [Container::RunConfiguration]
    def new_run_conf
      Container::RunConfiguration.new(self, load_conf: false)
    end

    # @return [Container::RunConfiguration]
    def get_run_conf
      run_conf || new_run_conf
    end

    # @return [Container::RunConfiguration, nil]
    def get_past_run_conf
      inclusively { @past_run_conf }
    end

    def forget_past_run_conf
      exclusively { @past_run_conf = nil }
    end

    # @param next_run_conf [Container::RunConfiguration]
    def set_next_run_conf(next_run_conf)
      exclusively { @next_run_conf = next_run_conf }
    end

    # This must be called on container start
    def init_run_conf
      exclusively do
        if @next_run_conf
          @run_conf = @next_run_conf
          @next_run_conf = nil
        else
          @run_conf = new_run_conf
        end

        @run_conf.save
      end
    end

    # Call {#init_run_conf} unless {#run_conf} is already set
    # @return [Container::RunConfiguration]
    def ensure_run_conf
      exclusively do
        init_run_conf if @run_conf.nil?
        run_conf
      end
    end

    # Mount the container's dataset
    # @param force [Boolean] ensure the datasets are mounted even if osctld
    #                        already mounted them
    def mount(force: false)
      return if !force && mounted
      dataset.mount(recursive: true)
      self.mounted = true
    end

    # Check if the container's dataset is mounted
    # @param force [Boolean] check if the dataset is mounted even if osctld
    #                        already mounted it
    def mounted?(force: false)
      if force || mounted.nil?
        self.mounted = dataset.mounted?(recursive: true)
      else
        mounted
      end
    end

    def chown(user)
      self.user = user
      save_config
      lxc_config.configure
      configure_bashrc
    end

    def chgrp(grp, missing_devices: nil)
      self.group = grp

      case missing_devices
      when 'provide'
        devices.ensure_all
        devices.create

      when 'remove'
        devices.remove_missing
        devices.create

      when 'check'
        devices.check_all_available!(grp)

      else
        fail "unsupported action for missing devices: '#{missing_devices}'"
      end

      save_config
      lxc_config.configure
      configure_bashrc
    end

    def state=(v)
      if state == :staged
        case v
        when :complete
          exclusively { @state = :stopped }
          save_config

        when :running
          exclusively { @state = v }
          save_config
        end

        return
      end

      exclusively { @state = v }
    end

    def current_state
      begin
        self.state = ContainerControl::Commands::State.run!(self).state
      rescue ContainerControl::Error
        self.state = :error
      end
    end

    def running?
      state == :running
    end

    def can_start?
      inclusively { state != :staged && state != :error && pool.active? }
    end

    def init_pid
      inclusively do
        @run_conf ? run_conf.init_pid : nil
      end
    end

    def starting
      exclusively do
        # Normally {#init_run_conf} is called from {Commands::Container::Start},
        # but in case the lxc-start was invoked manually outside of osctld,
        # initiate the run conf if needed.
        ensure_run_conf
      end
    end

    def stopped
      exclusively do
        if run_conf
          run_conf.destroy
          @past_run_conf = @run_conf
          @run_conf = nil
        end
      end
    end

    def can_dist_configure_network?
      inclusively do
        next false if netifs.detect { |netif| !netif.can_run_distconfig? }
        true
      end
    end

    def dir
      dataset.mountpoint
    end

    def lxc_home(user: nil, group: nil)
      inclusively { (group || self.group).userdir(user || self.user) }
    end

    def lxc_dir(user: nil, group: nil)
      inclusively { File.join(lxc_home(user: user, group: group), id) }
    end

    def rootfs
      File.join(dir, 'private')

    rescue SystemCommandFailed
      # Dataset for staged containers does not have to exist yet, relevant
      # primarily for ct show/list
      nil
    end

    def config_path
      inclusively { File.join(pool.conf_path, 'ct', "#{id}.yml") }
    end

    def user_hook_script_dir
      inclusively { File.join(pool.root_user_hook_script_dir, 'ct', id) }
    end

    def uid_map
      user.uid_map
    end

    def gid_map
      user.gid_map
    end

    def root_host_uid
      user.uid_map.ns_to_host(0)
    end

    def root_host_gid
      user.gid_map.ns_to_host(0)
    end

    # Return a list of all container datasets
    # @return [Array<OsCtl::Lib::Zfs::Dataset>]
    def datasets
      ds = inclusively { dataset }
      [ds] + ds.descendants
    end

    # Iterate over all container datasets
    # @yieldparam ds [OsCtl::Lib::Zfs::Dataset]
    def each_dataset(&block)
      datasets.each(&block)
    end

    def base_cgroup_path
      inclusively { File.join(group.full_cgroup_path(user), "ct.#{id}") }
    end

    def cgroup_path
      File.join(base_cgroup_path, 'user-owned')
    end

    def wrapper_cgroup_path
      File.join(base_cgroup_path, 'wrapper')
    end

    def entry_cgroup_path
      File.join(cgroup_path, "lxc.monitor.#{id}")
    end

    def abs_cgroup_path(subsystem)
      CGroup.abs_cgroup_path(subsystem, cgroup_path)
    end

    def abs_apply_cgroup_path(subsystem)
      CGroup.abs_cgroup_path(subsystem, base_cgroup_path)
    end

    # @return [Integer, nil] memory limit in bytes
    def find_memory_limit(parents: true)
      limit = cgparams.find_memory_limit

      if limit
        return limit
      elsif !parents
        return
      end

      group.find_memory_limit(parents: parents)
    end

    def set(opts)
      opts.each do |k, v|
        case k
        when :autostart
          self.autostart = AutoStart::Config.new(self, v[:priority], v[:delay])

        when :ephemeral
          self.ephemeral = true

        when :hostname
          original = nil

          exclusively do
            original = @hostname
            @hostname = OsCtl::Lib::Hostname.new(v)
          end

          DistConfig.run(get_run_conf, :set_hostname, original: original)

        when :dns_resolvers
          self.dns_resolvers = v
          DistConfig.run(get_run_conf, :dns_resolvers)

        when :nesting
          self.nesting = true

        when :distribution
          exclusively do
            @distribution = v[:name]
            @version = v[:version]
            @arch = v[:arch] if v[:arch]
          end

        when :seccomp_profile
          self.seccomp_profile = v

        when :init_cmd
          self.init_cmd = v

        when :start_menu
          self.start_menu = Container::StartMenu.new(self, v[:timeout])

        when :raw_lxc
          self.raw_configs.lxc = v

        when :attrs
          attrs.update(v)
        end
      end

      save_config
      lxc_config.configure_base
    end

    def unset(opts)
      opts.each do |k, v|
        case k
        when :autostart
          self.autostart = false
          pool.autostart_plan.stop_ct(self)

        when :ephemeral
          self.ephemeral = false

        when :hostname
          self.hostname = nil
          DistConfig.run(get_run_conf, :unset_etc_hosts)

        when :dns_resolvers
          self.dns_resolvers = nil

        when :nesting
          self.nesting = false

        when :seccomp_profile
          self.seccomp_profile = default_seccomp_profile

        when :init_cmd
          self.init_cmd = nil

        when :start_menu
          clear_start_menu
          self.start_menu = nil

        when :raw_lxc
          self.raw_configs.lxc = nil

        when :attrs
          v.each { |attr| attrs.unset(attr) }
        end
      end

      save_config
      lxc_config.configure_base
    end

    def prlimit_set(name, soft, hard)
      exclusively do
        limit = @prlimits.detect { |v| v.name == name }

        if limit
          limit.set(soft, hard)

        else
          @prlimits << PrLimit.new(name, soft, hard)
        end
      end

      save_config
      lxc_config.configure
    end

    def prlimit_unset(name)
      exclusively do
        limit = @prlimits.detect { |v| v.name == name }
        next unless limit
        @prlimits.delete(limit)
      end

      save_config
      lxc_config.configure_prlimits
    end

    def setup_start_menu
      menu = start_menu
      menu.deploy if menu
    end

    def clear_start_menu
      menu = start_menu
      menu.unlink if menu
    end

    def configure_bashrc
      ErbTemplate.render_to('ct/bashrc', {
        ct: self,
        override: %w(
          attach cgroup console device execute freeze info ls monitor stop top
          unfreeze wait
        ),
        disable: %w(
          autostart checkpoint clone copy create destroy snapshot
          start-ephemeral unshare
        ),
      }, File.join(lxc_dir, '.bashrc'))
    end

    def open_send_log(role, token, opts = {})
      exclusively do
        self.send_log = SendReceive::Log.new(role: role, token: token, opts: opts)
        save_config
      end
    end

    def close_send_log(save: true)
      exclusively do
        self.send_log.close
        self.send_log = nil
        save_config if save
      end
    end

    # Unregister the container from internal uses in osctld, e.g. on pool export
    def unregister
      exclusively do
        SendReceive::Tokens.free(send_log.token) if send_log
      end
    end

    # Export to clients
    def export
      inclusively do
        {
          pool: pool.name,
          id: id,
          user: user.name,
          group: group.name,
          uid_map: user.uid_map.map(&:to_h),
          gid_map: user.gid_map.map(&:to_h),
          dataset: dataset.name,
          rootfs: rootfs,
          boot_dataset: run_conf ? run_conf.dataset.name : dataset.name,
          boot_rootfs: run_conf ? run_conf.rootfs : rootfs,
          lxc_path: lxc_home,
          lxc_dir: lxc_dir,
          group_path: cgroup_path,
          distribution: run_conf ? run_conf.distribution : distribution,
          version: run_conf ? run_conf.version : version,
          state: state,
          init_pid: init_pid,
          autostart: autostart ? true : false,
          autostart_priority: autostart && autostart.priority,
          autostart_delay: autostart && autostart.delay,
          ephemeral: ephemeral,
          hostname: hostname,
          dns_resolvers: dns_resolvers,
          nesting: nesting,
          seccomp_profile: seccomp_profile,
          init_cmd: format_user_init_cmd,
          start_menu: start_menu ? true : false,
          start_menu_timeout: start_menu && start_menu.timeout,
          raw_lxc: raw_configs.lxc,
          log_file: log_path,
        }.merge!(attrs.export)
      end
    end

    # Dump to config
    def dump_config
      inclusively do
        data = {
          'user' => user.name,
          'group' => group.name,
          'dataset' => dataset.name,
          'distribution' => distribution,
          'version' => version,
          'arch' => arch,
          'net_interfaces' => netifs.dump,
          'cgparams' => cgparams.dump,
          'devices' => devices.dump,
          'prlimits' => prlimits.dump,
          'mounts' => mounts.dump,
          'autostart' => autostart && autostart.dump,
          'ephemeral' => ephemeral,
          'hostname' => hostname && hostname.to_s,
          'dns_resolvers' => dns_resolvers,
          'nesting' => nesting,
          'seccomp_profile' => seccomp_profile == default_seccomp_profile \
                               ? nil : seccomp_profile,
          'init_cmd' => init_cmd,
          'start_menu' => start_menu && start_menu.dump,
          'raw' => raw_configs.dump,
          'attrs' => attrs.dump,
        }

        data['state'] = 'staged' if state == :staged
        data['send_log'] = send_log.dump if send_log

        data
      end
    end

    def save_config
      data = dump_config

      File.open(config_path, 'w', 0400) do |f|
        f.write(OsCtl::Lib::ConfigFile.dump_yaml(data))
      end

      File.chown(0, 0, config_path)
    end

    def reload_config
      load_config_file
    end

    # @param config [String]
    def replace_config(config)
      load_config_string(config)
      save_config
    end

    # Update keys/values from `new_config` in the container's config
    # @param config [Hash]
    def patch_config(new_config)
      exclusively do
        tmp = dump_config
        tmp.update(new_config)
        load_config_hash(tmp)
        save_config
      end
    end

    def format_user_init_cmd
      (init_cmd || default_init_cmd).join(' ')
    end

    def format_exec_init_cmd
      cmd = (init_cmd || default_init_cmd)
      menu = start_menu

      if menu
        menu.init_cmd(cmd)
      else
        cmd
      end.join(' ')
    end

    def log_path
      inclusively { File.join(pool.log_path, 'ct', "#{id}.log") }
    end

    def log_type
      inclusively { "ct=#{pool.name}:#{id}" }
    end

    def manipulation_resource
      ['container', ident]
    end

    protected
    attr_exclusive_writer :pool, :id, :user, :dataset, :group, :distribution,
      :version, :arch, :autostart, :ephemeral, :hostname, :dns_resolvers,
      :nesting, :prlimits, :mounts, :send_log, :netifs, :cgparams,
      :devices, :seccomp_profile, :apparmor, :attrs, :lxc_config, :init_cmd,
      :start_menu
    attr_synchronized_accessor :mounted

    def load_config_file(path = nil, **opts)
      cfg = parse_yaml do
        OsCtl::Lib::ConfigFile.load_yaml_file(path || config_path)
      end

      load_config_hash(cfg, **opts)
    end

    def load_config_string(str, **opts)
      cfg = parse_yaml { OsCtl::Lib::ConfigFile.load_yaml(str) }
      load_config_hash(cfg, **opts)
    end

    def parse_yaml
      begin
        yield
      rescue Psych::Exception => e
        raise ConfigError.new("Unable to load config of container #{id}", e)
      end
    end

    def load_config_hash(cfg, init_devices: true, dataset_cache: nil)
      cfg = Container::Adaptor.adapt(self, cfg)

      exclusively do
        @state = cfg['state'].to_sym if cfg['state']
        @user ||= DB::Users.find(cfg['user'], pool) || (raise ConfigError.new(
          "container #{id}: user '#{cfg['user']}' not found"
        ))
        @group ||= DB::Groups.find(cfg['group'], pool) || (raise ConfigError.new(
          "container #{id}: group '#{cfg['group']}' not found"
        ))

        unless @dataset
          if cfg['dataset']
            @dataset = OsCtl::Lib::Zfs::Dataset.new(
              cfg['dataset'],
              base: cfg['dataset'],
              cache: dataset_cache,
            )
          else
            @dataset = Container.default_dataset(
              pool,
              id,
              dataset_cache: dataset_cache,
            )
          end
        end

        @distribution = cfg['distribution']
        @version = cfg['version']
        @arch = cfg['arch']
        @autostart = cfg['autostart'] && AutoStart::Config.load(self, cfg['autostart'])
        @ephemeral = cfg['ephemeral']
        @hostname = cfg['hostname'] && OsCtl::Lib::Hostname.new(cfg['hostname'])
        @dns_resolvers = cfg['dns_resolvers']
        @nesting = cfg['nesting'] || false
        @seccomp_profile = cfg['seccomp_profile'] || default_seccomp_profile
        @init_cmd = cfg['init_cmd']

        @start_menu =
          if !cfg.has_key?('start_menu') || cfg['start_menu']
            Container::StartMenu.load(self, cfg['start_menu'] || {})
          else
            nil
          end

        @run_conf = Container::RunConfiguration.load(self)

        if cfg['send_log']
          @send_log = SendReceive::Log.load(cfg['send_log'])
          SendReceive::Tokens.register(@send_log.token)
        end

        @cgparams = CGroup::ContainerParams.load(self, cfg['cgparams'])
        @prlimits = PrLimits::Manager.load(self, cfg['prlimits'] || {})
        @raw_configs = Container::RawConfigs.new(cfg['raw'] || {})
        @attrs = Attributes.load(cfg['attrs'] || {})

        # It's necessary to load devices _before_ netifs. The device manager needs
        # to create cgroups first, in order for echo a > devices.deny to work.
        # If the container has a veth interface, the setup code switches to the
        # container's user, which creates cgroups in all subsystems. Devices then
        # can't be initialized properly.
        @devices = Devices::ContainerManager.load(self, cfg['devices'] || [])
        @devices.init if init_devices

        @netifs = NetInterface::Manager.load(self, cfg['net_interfaces'] || [])
        @mounts = Mount::Manager.load(self, cfg['mounts'] || [])
      end
    end

    # Change the container so that it becomes a clone of `ct` with a different id
    # @param ct [Container] the source container
    # @param id [String] new container id
    # @param opts [Hash] options
    # @option opts [Pool] :pool target pool, optional
    # @option opts [User] :user target user, optional
    # @option opts [Group] :group target group, optional
    # @option opts [String] :dataset target dataset, optional
    # @option opts [Boolean] :network_interfaces
    def clone_from(ct, id, opts = {})
      init_lock
      init_manipulable

      @id = id
      @pool = opts[:pool] if opts[:pool]
      @user = opts[:user] if opts[:user]
      @group = opts[:group] if opts[:group]
      @state = :staged
      @send_log = nil

      if opts[:dataset]
        @dataset = OsCtl::Lib::Zfs::Dataset.new(
          opts[:dataset],
          base: opts[:dataset],
        )
      else
        @dataset = Container.default_dataset(@pool, @id)
      end

      @apparmor = @apparmor.dup(self)
      @autostart = @autostart && @autostart.dup(self)
      @cgparams = cgparams.dup(self)
      @prlimits = prlimits.dup(self)
      @mounts = mounts.dup(self)
      @start_menu = @start_menu && @start_menu.dup(self)
      @lxc_config = lxc_config.dup(self)
      @raw_configs = raw_configs.dup
      @attrs = attrs.dup
      @run_conf = nil
      @next_run_conf = nil
      @past_run_conf = nil

      @devices = devices.dup(self)
      devices.init

      if opts[:network_interfaces]
        @netifs = netifs.dup(self)
        netifs.each(&:setup)
      else
        @netifs = NetInterface::Manager.new(self)
      end
    end

    def default_seccomp_profile
      '/etc/lxc/config/common.seccomp'
    end

    def default_init_cmd
      ['/sbin/init']
    end
  end
end
