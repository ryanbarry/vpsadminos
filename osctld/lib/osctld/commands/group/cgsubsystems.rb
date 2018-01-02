module OsCtld
  class Commands::Group::CGSubsystems < Commands::Base
    handle :group_cgsubsystems

    def execute
      ret = {}

      %w(cpu cpuacct memory).each do |v|
        ret[v] = File.join(CGroup::FS, CGroup.real_subsystem(v))
      end

      ok(ret)
    end
  end
end
