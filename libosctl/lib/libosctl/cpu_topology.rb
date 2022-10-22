module OsCtl::Lib
  class CpuTopology
    # @!attribute [r] id
    #   @return [Integer] Package ID
    # @!attribute [r] cpus
    #   @return [Hash<Integer, Cpu>]
    Package = Struct.new(:id, :cpus, keyword_init: true)

    # @!attribute [r] id
    #   @return [Integer] CPU ID
    # @!attribute [r] package_id
    #   @return [Integer] Package ID
    Cpu = Struct.new(:id, :package_id, keyword_init: true)

    # @return [Hash<Integer, Package>]
    attr_reader :packages

    # @return [Hash<Integer, Cpu>]
    attr_reader :cpus

    def initialize
      parse
    end

    protected
    def parse
      @packages = {}
      @cpus = {}

      sys_dir = '/sys/devices/system/cpu'
      cpu_list = []

      Dir.glob(File.join(sys_dir, 'cpu*')).each do |f|
        next unless /\/cpu(\d+)$/ =~ f
        cpu_list << $1.to_i
      end

      cpu_list.sort.each do |cpu_id|
        pkg_id = File.read(File.join(sys_dir, "cpu#{cpu_id}", 'topology/physical_package_id')).strip.to_i

        cpu = Cpu.new(id: cpu_id, package_id: pkg_id)

        @cpus[cpu.id] = cpu

        @packages[pkg_id] ||= Package.new(id: pkg_id, cpus: {})
        @packages[pkg_id].cpus[cpu.id] = cpu
      end
    end
  end
end
