require 'osctl/cli/command'
require 'osctl/cli/assets'

module OsCtl::Cli
  class Self < Command
    include Assets

    SHUTDOWN_MARKER = '/run/osctl/shutdown'

    def assets
      print_assets(:self_assets)
    end

    def healthcheck
      entities = osctld_call(
        :self_healthcheck,
        all: opts[:all],
        pools: (opts[:all] || args.empty?) ? nil : args
      )

      if gopts[:json]
        puts entities.to_json
        return
      end

      if entities.empty?
        puts 'No errors detected.'
        return
      end

      entities.each do |ent|
        puts "#{ent[:type]} #{ent[:pool] || '-'} #{ent[:id] || '-'}"

        ent[:assets].each do |asset|
          puts "\t#{asset[:type]} #{asset[:path]}: #{asset[:errors].join('; ')}"
        end
      end
    end

    def ping
      if args[0]
        secs = args[0].to_i

        (0..Float::INFINITY).each do |i|
          begin
            return if do_ping

          rescue GLI::CustomExit
            raise if secs > 0 && i >= secs
          end

          sleep(1)
        end

      else
        puts 'pong' if do_ping
      end
    end

    def activate
      osctld_fmt(:self_activate, cmd_opts: {system: opts[:system], lxcfs: opts[:lxcfs]})
    end

    def shutdown
      if opts[:abort]
        osctld_fmt(:self_abort_shutdown)
        return
      end

      unless opts[:force]
        STDOUT.write(
          'Do you really wish to stop all containers and export all pools? '+
          '[y/N]: '
        )

        if !%w(y yes).include?(STDIN.readline.strip.downcase)
          puts 'Aborting'
          return
        end
      end

      # Ensure osctld will shutdown even if it crashes/restarts
      File.open(SHUTDOWN_MARKER, 'w', 0000){}

      begin
        osctld_fmt(:self_shutdown)
        return
      rescue OsCtl::Client::Error => e
        warn "Lost connection to osctld: #{e.message}"
      rescue Errno::ENOENT
        warn 'Unable to connect to osctld: socket not found'
      end

      STDOUT.write('Waiting for osctld to prepare for shutdown...')
      STDOUT.flush

      (0..3600).each do |i|
        begin
          st = File.stat(SHUTDOWN_MARKER)
          if st.mode & 0100 == 0100
            warn ' ok'
            return
          end
        rescue Errno::ENOENT
          warn 'Shutdown mark does not exist, osctld will not shutdown'
          return
        end

        if i % 5 == 0
          STDOUT.write('.')
          STDOUT.flush
        end

        sleep(1)
      end

      warn
      warn 'Waited for an hour, going to shutdown'
    end

    protected
    def do_ping
      return true if osctld_call(:self_ping) == 'pong'
      raise GLI::CustomExit.new('unexpected response', 3)

    rescue Errno::ENOENT
      raise GLI::CustomExit.new('unable to connect', 2)

    rescue OsCtl::Client::Error
      raise GLI::CustomExit.new('invalid response', 3)
    end
  end
end
