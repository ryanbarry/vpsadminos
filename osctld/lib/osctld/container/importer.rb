require 'fileutils'
require 'libosctl'
require 'rubygems'
require 'rubygems/package'

module OsCtld
  # An interface for reading tar archives generated by
  # {OsCtl::Lib::Container::Exporter}
  class Container::Importer
    BLOCK_SIZE = 32 * 1024

    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System

    def initialize(pool, io, ct_id: nil, image_file: nil)
      @pool = pool
      @tar = Gem::Package::TarReader.new(io)
      @image_file = image_file
      @ct_id = ct_id
    end

    # Load metadata describing the archive
    #
    # Loading the metadata is the first thing that should be done, because all
    # other methods depend on its result.
    def load_metadata
      ret = tar.seek('metadata.yml') do |entry|
        OsCtl::Lib::ConfigFile.load_yaml(entry.read)
      end
      raise 'metadata.yml not found' unless ret

      @metadata = ret
      ret
    end

    def user_name
      metadata['user']
    end

    def has_user?
      !user_name.nil?
    end

    def group_name
      metadata['group']
    end

    def has_group?
      !group_name.nil?
    end

    def ct_id
      @ct_id || metadata['container']
    end

    def has_ct_id?
      !ct_id.nil?
    end

    # Create a new instance of {User} as described by the tar archive
    #
    # The returned user is not registered in the internal database, it may even
    # conflict with a user already registered in the database.
    # @return [User, nil]
    def load_user
      return unless has_user?

      User.new(
        pool,
        metadata['user'],
        config: tar.seek('config/user.yml', &:read)
      )
    end

    # Create a new instance of {Group} as described by the tar archive
    #
    # The returned group is not registered in the internal database, it may even
    # conflict with a group already registered in the database.
    # @return [Group, nil]
    def load_group
      return unless has_group?

      Group.new(
        pool,
        metadata['group'],
        config: tar.seek('config/group.yml', &:read),
        devices: false
      )
    end

    # Create a new instance of {Container} as described by the tar archive
    #
    # The returned CT is not registered in the internal database, it may even
    # conflict with a CT already registered in the database.
    #
    # @param opts [Hash] options
    # @option opts [String] id defaults to id from the archive
    # @option opts [User] user calls {#get_or_create_user} by default
    # @option opts [Group] group calls {#get_or_create_group} by default
    # @option opts [String] dataset
    # @option opts [Hash] ct_opts container options
    # @return [Container]
    def load_ct(opts)
      id = opts[:id] || metadata['container']
      user = opts[:user] || get_or_create_user
      group = opts[:group] || get_or_create_group
      ct_opts = opts[:ct_opts] || {}
      ct_opts[:load_from] = tar.seek('config/container.yml', &:read)

      Container.new(
        pool,
        id,
        user,
        group,
        opts[:dataset] || Container.default_dataset(pool, id),
        ct_opts
      )
    end

    # @return [Hash]
    def get_container_config
      OsCtl::Lib::ConfigFile.load_yaml(tar.seek('config/container.yml', &:read))
    end

    # Load the user from the archive and register him, or create a new user
    #
    # If a user with the same name already exists and all his parameters are the
    # same, the existing user is returned. Otherwise an exception is raised.
    # @return [User]
    def get_or_create_user
      if has_user?
        load_or_create_user
      else
        create_new_user
      end
    end

    # Load the group from the archive and register it, or create a new group
    #
    # If a group with the same name already exists and all its parameters are the
    # same, the existing group is returned. Otherwise an exception is raised.
    # @return [Group]
    def get_or_create_group
      if has_group?
        name = metadata['group']

        db = DB::Groups.find(name, pool)
        grp = load_group

        if db.nil?
          # The group does not exist, create it
          Commands::Group::Create.run!(
            pool: pool.name,
            name: grp.name
          )

          return DB::Groups.find(name, pool) || (raise 'expected group')
        end

        db

      else
        DB::Groups.default(pool)
      end
    end

    # Load user-defined script hooks from the archive and install them
    # @param ct [Container]
    def install_user_hook_scripts(ct)
      tar.each do |entry|
        next unless entry.full_name.start_with?('hooks/')

        name = entry.full_name[('hooks/'.length - 1)..-1]

        if entry.directory?
          FileUtils.mkdir_p(
            File.join(ct.user_hook_script_dir, name),
            mode: entry.header.mode & 0o7777
          )
        elsif entry.file?
          copy_file_to_disk(entry, File.join(ct.user_hook_script_dir, name))
        end
      end
    end

    # Create the root and all descendants datasets
    #
    # @param builder [Container::Builder]
    # @param accept_existing [Boolean]
    def create_datasets(builder, accept_existing: false)
      datasets(builder).each do |ds|
        next if accept_existing && ds.exist?

        builder.create_dataset(ds, mapping: true, parents: ds.root?)
      end
    end

    # Import all datasets
    # @param builder [Container::Builder]
    def import_all_datasets(builder)
      case metadata['format']
      when 'zfs'
        import_streams(builder, datasets(builder))

      when 'tar'
        unpack_rootfs(builder)

      else
        raise "unsupported archive format '#{metadata['format']}'"
      end
    end

    # Import just the root dataset
    # @param builder [Container::Builder]
    def import_root_dataset(builder)
      case metadata['format']
      when 'zfs'
        import_streams(builder, [datasets(builder).first])

      when 'tar'
        unpack_rootfs(builder)

      else
        raise "unsupported archive format '#{metadata['format']}'"
      end
    end

    # @param builder [Container::Builder]
    # @return [Array<OsCtl::Lib::Zfs::Dataset>]
    def datasets(builder)
      return @datasets if @datasets

      @datasets = [builder.ctrc.dataset] + metadata['datasets'].map do |name|
        OsCtl::Lib::Zfs::Dataset.new(
          File.join(builder.ctrc.dataset.name, name),
          base: builder.ctrc.dataset.name
        )
      end
    end

    def close
      tar.close
    end

    protected

    attr_reader :pool, :tar, :image_file, :metadata

    # @return [User]
    def load_or_create_user
      name = metadata['user']

      db = DB::Users.find(name, pool)
      u = load_user

      if db.nil?
        # The user does not exist, create him
        Commands::User::Create.run!(
          pool: pool.name,
          name: u.name,
          ugid: u.ugid,
          uid_map: u.uid_map.export,
          gid_map: u.gid_map.export
        )

        return DB::Users.find(name, pool) || (raise 'expected user')
      end

      # Free the newly allocated ugid, use ugid from the existing user
      UGidRegistry.remove(u.ugid) if u.ugid != db.ugid

      %i[uid_map gid_map].each do |param|
        mine = db.send(param)
        other = u.send(param)
        next if mine == other

        raise "user #{pool.name}:#{name} already exists: #{param} mismatch: " +
              "existing #{mine}, trying to import #{other}"
      end

      db
    end

    # @return [User]
    def create_new_user
      name = ct_id

      db = DB::Users.find(name, pool)
      return db if db

      # The user does not exist, create him
      Commands::User::Create.run!(
        pool: pool.name,
        name:,
        standalone: false
      )

      DB::Users.find(name, pool) || (raise 'expected user')
    end

    # Load ZFS data streams from the archive and write them to appropriate
    # datasets
    #
    # @param builder [Container::Builder]
    # @param datasets [Array<OsCtl::Lib::Zfs::Dataset>]
    def import_streams(builder, datasets)
      datasets.each do |ds|
        import_stream(builder, ds, File.join(ds.relative_name, 'base'), true)
        import_stream(builder, ds, File.join(ds.relative_name, 'incremental'), false)
      end

      tar.seek('snapshots.yml') do |entry|
        snapshots = OsCtl::Lib::ConfigFile.load_yaml(entry.read)

        datasets(builder).each do |ds|
          snapshots.each { |snap| zfs(:destroy, nil, "#{ds}@#{snap}") }
        end
      end
    end

    # @param builder [Container::Builder]
    def unpack_rootfs(builder)
      raise 'image_file needs to be set for import_stream()' if image_file.nil?

      # Ensure the dataset is mounted
      builder.ctrc.dataset.mount(recursive: true)

      # Create private/
      builder.setup_rootfs

      tf = tar.find { |entry| entry.full_name == 'rootfs/base.tar.gz' }
      raise 'rootfs archive not found' if tf.nil?

      tar.rewind

      commands = [
        ['tar', '-xOf', image_file, tf.full_name],
        ['tar', '--xattrs-include=security.capability', '--xattrs', '-xz', '-C', builder.ctrc.rootfs]
      ]

      command_string = commands.map { |c| c.join(' ') }.join(' | ')

      pid = Process.spawn(command_string)
      Process.wait(pid)

      return unless $?.exitstatus != 0

      raise "failed to unpack rootfs: command '#{command_string}' " +
            "exited with #{$?.exitstatus}"
    end

    def import_stream(builder, ds, name, required)
      raise 'image_file needs to be set for import_stream()' if image_file.nil?

      found = nil

      stream_names(name).each do |file, compression|
        tf = tar.find { |entry| entry.full_name == file }

        if tf.nil?
          tar.rewind
          next
        end

        found = [tf, compression]
        break
      end

      if found.nil?
        tar.rewind
        raise "unable to import: #{name} not found" if required

        return
      end

      entry, compression = found
      builder.from_tar_stream(image_file, entry.full_name, compression, ds)
      tar.rewind
    end

    def stream_names(name)
      base = File.join('rootfs', "#{name}.dat")
      [[base, :off], ["#{base}.gz", :gzip]]
    end

    # Copy file from the tar archive to disk
    # @param entry [Gem::Package::TarReader::Entry]
    # @param dst [String]
    def copy_file_to_disk(entry, dst)
      File.open(dst, 'w', entry.header.mode & 0o7777) do |df|
        df.write(entry.read(BLOCK_SIZE)) until entry.eof?
      end
    end
  end
end
