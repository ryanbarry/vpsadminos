require 'fileutils'
require 'libosctl'
require 'osctld/lockable'
require 'osctld/manipulable'
require 'osctld/assets/definition'

module OsCtld
  # This class represents a data pool
  #
  # Data pool contains users, groups and containers, both data
  # and configuration. Each user/group/ct belongs to exactly one pool.
  class Pool
    PROPERTY_ACTIVE = 'org.vpsadminos.osctl:active'.freeze
    PROPERTY_DATASET = 'org.vpsadminos.osctl:dataset'.freeze
    CT_DS = 'ct'.freeze
    CONF_DS = 'conf'.freeze
    HOOK_DS = 'hook'.freeze
    LOG_DS = 'log'.freeze
    REPOSITORY_DS = 'repository'.freeze
    MIGRATION_DS = 'migration'.freeze
    TRASH_BIN_DS = 'trash'.freeze

    OPTIONS = %i[parallel_start parallel_stop].freeze

    include Lockable
    include Manipulable
    include Assets::Definition
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include OsCtl::Lib::Utils::File
    include OsCtl::Lib::Utils::Exception

    attr_reader :name, :dataset, :state, :send_receive_key_chain, :autostart_plan,
                :autostop_plan, :trash_bin, :garbage_collector, :attrs

    def initialize(name, dataset)
      init_lock
      init_manipulable

      @name = name
      @dataset = dataset || name
      @state = :importing
      @attrs = Attributes.new
      @abort_export = false
    end

    def init
      exclusively do
        load_config

        @send_receive_key_chain = SendReceive::KeyChain.new(self)
        @autostart_plan = AutoStart::Plan.new(self)
        @autostop_plan = AutoStop::Plan.new(self)
        @trash_bin = TrashBin.new(self)
        @garbage_collector = GarbageCollector.new(self)
        @hint_updater = HintUpdater.new(self)
      end
    end

    def id
      name
    end

    def pool
      self
    end

    def assets
      define_assets do |add|
        # Datasets
        add.dataset(
          ds(CT_DS),
          desc: 'Contains container root filesystems',
          user: 0,
          group: 0,
          mode: 0o511
        )
        add.dataset(
          ds(CONF_DS),
          desc: 'Configuration files',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.dataset(
          ds(HOOK_DS),
          desc: 'User supplied script hooks',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.dataset(
          ds(LOG_DS),
          desc: 'Container log files, pool history',
          user: 0,
          group: 0,
          mode: 0o511
        )
        add.dataset(
          ds(REPOSITORY_DS),
          desc: 'Local image repository cache',
          user: Repository::UID,
          group: 0,
          mode: 0o500
        )
        add.dataset(
          ds(MIGRATION_DS),
          desc: 'Data for OS migrations',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.dataset(
          ds(TRASH_BIN_DS),
          desc: 'Trash bin',
          user: 0,
          group: 0,
          mode: 0o500
        )

        # Configs
        add.directory(
          File.join(conf_path, 'pool'),
          desc: 'Pool configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.file(
          config_path,
          desc: 'Pool configuration file for osctld',
          optional: true
        )
        add.directory(
          File.join(conf_path, 'user'),
          desc: 'User configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.directory(
          File.join(conf_path, 'group'),
          desc: 'Group configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.directory(
          File.join(conf_path, 'ct'),
          desc: 'Container configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.directory(
          File.join(conf_path, 'send-receive'),
          desc: 'Identity and authorized keys for container send/receive',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.directory(
          File.join(conf_path, 'repository'),
          desc: 'Repository configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0o500
        )
        add.directory(
          File.join(conf_path, 'id-range'),
          desc: 'ID range configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0o500
        )

        # Logs
        add.directory(
          File.join(log_path, 'ct'),
          desc: 'Container log files',
          user: 0,
          group: 0
        )

        # Hooks
        add.directory(
          File.join(user_hook_script_dir),
          desc: 'User supplied pool script hooks',
          user: 0,
          group: 0
        )
        add.directory(
          File.join(root_user_hook_script_dir, 'ct'),
          desc: 'User supplied container script hooks',
          user: 0,
          group: 0
        )

        # Pool history
        History.assets(pool, add)

        # Send/Receive
        send_receive_key_chain.assets(add)

        # Runstate
        add.directory(
          run_dir,
          desc: 'Runtime configuration',
          user: 0,
          group: 0,
          mode: 0o711
        )
        add.directory(
          user_dir,
          desc: 'Contains user homes and LXC configuration',
          user: 0,
          group: 0,
          mode: 0o511
        )
        add.directory(
          ct_dir,
          desc: 'Contains runtime container state data',
          user: 0,
          group: 0,
          mode: 0o700
        )
        add.directory(
          console_dir,
          desc: 'Sockets for container consoles',
          user: 0,
          group: 0,
          mode: 0o711
        )
        add.directory(
          hook_dir,
          desc: 'Container hooks',
          user: 0,
          group: 0,
          mode: 0o711
        )
        add.directory(
          mount_dir,
          desc: 'Mount helper directories for containers',
          user: 0,
          group: 0,
          mode: 0o711
        )

        if AppArmor.enabled?
          add.directory(
            apparmor_dir,
            desc: 'AppArmor files',
            user: 0,
            group: 0,
            mode: 0o700
          )

          AppArmor.assets(add, pool)
        end

        add.directory(
          autostart_dir,
          desc: 'Contains runtime container auto-start state',
          user: 0,
          group: 0,
          mode: 0o700
        )

        autostart_plan.assets(add) if autostart_plan
        garbage_collector.assets(add)
      end
    end

    def setup
      # Ensure needed datasets are present
      mkdatasets

      # Setup run state, i.e. hooks
      runstate

      # Load ID ranges
      load_id_ranges

      # Load users from zpool
      load_users

      # Register loaded users into the system
      Commands::User::Register.run(all: true)

      # Generate /etc/subuid and /etc/subgid
      Commands::User::SubUGIds.run

      # Setup BPF FS
      BpfFs.add_pool(name)
      Devices::V2::BpfProgramCache.load_links(name)

      # Load groups
      load_groups

      # Load containers from zpool
      load_cts

      # Setup AppArmor profiles
      AppArmor.setup_pool(pool) if AppArmor.enabled?

      # Allow containers to create veth interfaces
      Commands::User::LxcUsernet.run

      # Load send/receive keys
      send_receive_key_chain.setup
      SendReceive.deploy

      # Load repositories
      load_repositories

      # Open history
      History.open(self)

      # Start trash-bin GC
      trash_bin.start

      # Start garbage collector
      garbage_collector.start

      exclusively { @state = :active }

      # Schedule hint updates
      @hint_updater.start
    end

    # Set pool options
    # @param opts [Hash]
    # @option opts [Integer] :parallel_start
    # @option opts [Integer] :parallel_stop
    # @option opts [Hash] :attrs
    def set(opts)
      opts.each do |k, v|
        case k
        when :parallel_start
          instance_variable_set(:"@#{k}", opts[k])
          pool.autostart_plan.resize(opts[k])

        when :parallel_stop
          instance_variable_set(:"@#{k}", opts[k])
          pool.autostop_plan.resize(opts[k])

        when :attrs
          attrs.update(v)

        else
          raise "unsupported option '#{k}'"
        end
      end

      save_config
    end

    # Reset pool options
    # @param opts [Hash]
    # @option opts [Array<Symbol>] :options
    # @option opts [Array<String>] :attrs
    def unset(opts)
      opts.each do |k, v|
        case k
        when :options
          OPTIONS.each do |opt|
            next unless v.include?(opt)

            remove_instance_variable(:"@#{opt}")
          end

        when :attrs
          v.each { |attr| attrs.unset(attr) }
        end
      end

      save_config
    end

    def autostart(force: false)
      Hook.run(self, :pre_autostart)
      autostart_plan.start(force:)
    end

    def autostop_and_wait(message: nil, client_handler: nil)
      autostop_plan.start(message:, client_handler:)
      autostop_plan.wait
    end

    def autostop_no_wait(message: nil, client_handler: nil, progress_tracker: nil)
      autostop_plan.start(message:, client_handler:, progress_tracker:)
    end

    def wait_for_autostop
      autostop_plan.wait
    end

    def fulfil_autostart(ct)
      autostart_plan.fulfil_start(ct)
    end

    def request_reboot(ct)
      autostart_plan.request_reboot(ct)
    end

    def fulfil_reboot(ct)
      autostart_plan.fulfil_reboot(ct)
    end

    def begin_stop
      autostart_plan.stop if autostart_plan.started?
      trash_bin.stop if trash_bin.started?
    end

    def all_stop
      autostop_plan.stop
      @hint_updater.stop
    end

    def stop
      begin_stop
      all_stop
    end

    def begin_export
      @abort_export = false
    end

    def abort_export
      @abort_export = true
      autostop_plan.clear
    end

    def abort_export?
      @abort_export
    end

    def active?
      state == :active
    end

    def imported?
      state != :importing
    end

    def disabled?
      state == :disabled
    end

    def disable
      @state = :disabled
    end

    def ct_ds
      ds(CT_DS)
    end

    def trash_bin_ds
      ds(TRASH_BIN_DS)
    end

    def conf_path
      path(CONF_DS)
    end

    def log_path
      path(LOG_DS)
    end

    def root_user_hook_script_dir
      path(HOOK_DS)
    end

    def user_hook_script_dir
      File.join(root_user_hook_script_dir, 'pool')
    end

    def repo_path
      path(REPOSITORY_DS)
    end

    def log_type
      "pool=#{name}"
    end

    def manipulation_resource
      ['pool', name]
    end

    def run_dir
      File.join(RunState::POOL_DIR, name)
    end

    def user_dir
      File.join(run_dir, 'users')
    end

    def ct_dir
      File.join(run_dir, 'containers')
    end

    def autostart_dir
      File.join(run_dir, 'auto-start')
    end

    def hook_dir
      File.join(run_dir, 'hooks')
    end

    def console_dir
      File.join(run_dir, 'console')
    end

    def mount_dir
      File.join(run_dir, 'mounts')
    end

    def apparmor_dir
      File.join(run_dir, 'apparmor')
    end

    def config_path
      File.join(conf_path, 'pool', 'config.yml')
    end

    # Pool option accessors
    OPTIONS.each do |k|
      define_method(k) do
        v = instance_variable_get("@#{k}")
        v.nil? ? default_opts[k] : v
      end
    end

    protected

    def load_config
      return unless File.exist?(config_path)

      cfg = OsCtl::Lib::ConfigFile.load_yaml_file(config_path)

      @parallel_start = cfg['parallel_start']
      @parallel_stop = cfg['parallel_stop']
      @attrs = Attributes.load(cfg['attrs'] || {})
    end

    def default_opts
      {
        parallel_start: 2,
        parallel_stop: 4
      }
    end

    def dump_opts
      ret = {}

      OPTIONS.each do |k|
        v = instance_variable_get("@#{k}")
        ret[k.to_s] = v unless v.nil?
      end

      ret
    end

    def save_config
      regenerate_file(config_path, 0o400) do |f|
        f.write(OsCtl::Lib::ConfigFile.dump_yaml(dump_opts.merge(attrs.dump)))
      end
    end

    def mkdatasets
      log(:info, 'Ensuring presence of base datasets and directories')
      zfs(:create, '-p', ds(CT_DS))
      zfs(:create, '-p', ds(CONF_DS))
      zfs(:create, '-p', ds(HOOK_DS))
      zfs(:create, '-p', ds(LOG_DS))
      zfs(:create, '-p', ds(REPOSITORY_DS))
      zfs(:create, '-p', ds(MIGRATION_DS))
      zfs(:create, '-p', ds(TRASH_BIN_DS))

      File.chmod(0o511, path(CT_DS))
      File.chmod(0o500, path(CONF_DS))
      File.chmod(0o500, path(HOOK_DS))
      File.chmod(0o511, path(LOG_DS))

      File.chown(Repository::UID, 0, path(REPOSITORY_DS))
      File.chmod(0o500, path(REPOSITORY_DS))

      File.chmod(0o500, path(MIGRATION_DS))
      File.chmod(0o500, path(TRASH_BIN_DS))

      # Configuration directories
      %w[pool ct group user send-receive repository id-range].each do |dir|
        path = File.join(conf_path, dir)
        FileUtils.mkdir_p(path, mode: 0o500)
      end

      [
        File.join(root_user_hook_script_dir, 'ct'),
        user_hook_script_dir,
        File.join(log_path, 'ct')
      ].each do |path|
        FileUtils.mkdir_p(path)
      end
    end

    def load_id_ranges
      log(:info, 'Loading ID ranges')
      DB::IdRanges.setup(self)

      Dir.glob(File.join(conf_path, 'id-range', '*.yml')).each do |f|
        name = File.basename(f)[0..(('.yml'.length + 1) * -1)]
        next if name == 'default'

        range = load_entity('id-range', name) { IdRange.new(self, name) }
        next unless range

        DB::IdRanges.add(range)
      end
    end

    def load_users
      log(:info, 'Loading users')

      Dir.glob(File.join(conf_path, 'user', '*.yml')).each do |f|
        name = File.basename(f)[0..(('.yml'.length + 1) * -1)]
        u = load_entity('user', name) { User.new(self, name) }
        next if !u || !check_user_conflict(u)

        Commands::User::Setup.run!(user: u)
      end
    end

    def load_groups
      log(:info, 'Loading groups')
      DB::Groups.setup(self)

      rx = %r{^#{Regexp.escape(File.join(conf_path, 'group'))}(.*)/config\.yml$}

      Dir.glob(File.join(conf_path, 'group', '**', 'config.yml')).each do |file|
        next unless rx =~ file

        name = ::Regexp.last_match(1)
        next if ['', '/default'].include?(name)

        grp = load_entity('group', name) do
          Group.new(self, name, devices: false)
        end
        next unless grp

        DB::Groups.add(grp)
      end

      # The devices in the root group have to be configured as soon as possible,
      # because `echo a > devices.deny` will not work when the root cgroup has
      # any children.
      root = DB::Groups.root(self)

      # Initialize devices of all groups, from the root group down
      root.descendants.each do |grp|
        grp.devices.init
      end
    end

    def load_cts
      log(:info, 'Loading containers')

      ds_cache = OsCtl::Lib::Zfs::DatasetCache.new(
        OsCtl::Lib::Zfs::Dataset.new(ds(CT_DS)).list(properties: %w[name mountpoint])
      )

      ep = ExecutionPlan.new

      Dir.glob(File.join(conf_path, 'ct', '*.yml')).each do |f|
        ep << File.basename(f)[0..(('.yml'.length + 1) * -1)]
      end

      log(:info, "Going to load #{ep.length} containers, #{ep.default_threads} at a time")

      ep.run do |ctid|
        log(:info, "Loading container #{ctid}")

        ct = load_entity('container', ctid) do
          Container.new(self, ctid, nil, nil, nil, dataset_cache: ds_cache)
        end
        next unless ct

        ensure_limits(ct)

        builder = Container::Builder.new(ct.get_run_conf)
        builder.setup_lxc_home
        builder.setup_log_file

        ct.reconfigure

        running = ct.fresh_state == :running

        ct.ensure_run_conf if running
        Monitor::Master.monitor(ct)
        Console.reconnect_tty0(ct) if running

        DB::Containers.add(ct)
      end

      ep.wait
      log(:info, 'All containers loaded')
    end

    def load_repositories
      log(:info, 'Loading repositories')
      DB::Repositories.setup(self)

      Dir.glob(File.join(conf_path, 'repository', '*.yml')).each do |f|
        name = File.basename(f)[0..(('.yml'.length + 1) * -1)]
        next if name == 'default'

        repo = load_entity('repository', name) { Repository.new(self, name) }
        next unless repo

        DB::Repositories.add(repo)
      end
    end

    def load_entity(type, name)
      yield
    rescue ConfigError => e
      if e.original_exception
        log(:fatal, "#{type} #{name}: #{e.message}: #{e.original_exception.message} (#{e.original_exception.class})")
        log(:fatal, denixstorify(e.original_exception.backtrace).join("\n"))
      else
        log(:fatal, "Unable to load config of #{type} #{name}: #{e.message}")
      end

      nil
    end

    def runstate
      FileUtils.mkdir_p(run_dir, mode: 0o711)

      if Dir.exist?(user_dir)
        File.chmod(0o511, user_dir)
      else
        Dir.mkdir(user_dir, 0o511)
      end
      File.chown(0, 0, user_dir)

      [console_dir, hook_dir, mount_dir].each do |dir|
        FileUtils.mkdir_p(dir, mode: 0o711)
      end

      [ct_dir, apparmor_dir, autostart_dir].each do |dir|
        FileUtils.mkdir_p(dir, mode: 0o700)
      end

      %w[
        ct-pre-start
        ct-pre-mount
        ct-post-mount
        ct-autodev
        ct-on-start
        ct-post-stop
      ].each do |hook|
        symlink = OsCtld.hook_run(hook, self)
        hook_src = OsCtld.hook_src(hook)

        if File.symlink?(symlink)
          next if File.readlink(symlink) == hook_src

          File.unlink(symlink)

        end

        File.symlink(hook_src, symlink)
      end
    end

    def check_user_conflict(user)
      DB::Users.sync do
        if (u = DB::Users.by_ugid(user.ugid))
          log(
            :warn,
            "Unable to load user '#{user.name}': " \
            "user/group ID #{user.ugid} already taken by pool '#{u.pool.name}'"
          )
          return false
        end
      end

      true
    end

    def ensure_limits(ct)
      return unless ct.prlimits.contains?('nofile')

      SystemLimits.ensure_nofile(ct.prlimits['nofile'].hard)
    end

    def ds(path)
      File.join(dataset, path)
    end

    def path(ds = '')
      File.join('/', dataset, ds)
    end
  end
end
