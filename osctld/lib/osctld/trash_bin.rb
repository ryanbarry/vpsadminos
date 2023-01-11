require 'libosctl'
require 'securerandom'

module OsCtld
  class TrashBin
    # @param pool [Pool]
    # @param dataset [OsCtl::Lib::Zfs::Dataset]
    def self.add_dataset(pool, dataset)
      pool.trash_bin.add_dataset(dataset)
    end

    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System

    # @return [Pool]
    attr_reader :pool

    # @param pool [Pool]
    def initialize(pool)
      @pool = pool
      @trash_dataset = OsCtl::Lib::Zfs::Dataset.new(pool.trash_bin_ds)
      @queue = OsCtl::Lib::Queue.new
      @stop = false
    end

    def start
      @stop = false
      @thread = Thread.new { run_gc }
    end

    def stop
      if @thread
        @stop = true
        @queue << :stop
        @thread.join
        @thread = nil
      end
    end

    def prune
      @queue << :prune
    end

    # @param dataset [OsCtl::Lib::Zfs::Dataset]
    def add_dataset(dataset)
      zfs(:rename, nil, "#{dataset} #{trash_path(dataset)}")
    end

    def log_type
      "#{pool.name}:trash"
    end

    protected
    def run_gc
      loop do
        v = @queue.pop(timeout: 6*60*60)
        return if v == :stop

        log(:info, 'Pruning')
        prune_datasets
      end
    end

    def prune_datasets
      txg_timeout = File.read('/sys/module/zfs/parameters/zfs_txg_timeout').strip.to_i

      @trash_dataset.list(depth: 1, include_self: false).each do |ds|
        break if @stop

        log(:info, "Destroying #{ds}")

        begin
          ds.destroy!(recursive: true)
        rescue SystemCommandFailed => e
          log(:warn, "Unable to destroy #{ds}: #{e.message}")
          next
        end

        break if @stop
        sleep([txg_timeout, 5].max)
      end
    end

    def trash_path(dataset)
      File.join(
        @trash_dataset.name,
        [
          dataset.name.split('/')[1..-1].join('-'),
          Time.now.to_i,
          SecureRandom.hex(3),
        ].join('.'),
      )
    end
  end
end