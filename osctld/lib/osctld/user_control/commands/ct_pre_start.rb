require 'libosctl'
require 'osctld/user_control/commands/base'

module OsCtld
  class UserControl::Commands::CtPreStart < UserControl::Commands::Base
    handle :ct_pre_start

    include OsCtl::Lib::Utils::Log

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      return error('container not found') unless ct
      return error('access denied') unless owns_ct?(ct)

      ct.starting

      # Mount datasets
      ct.run_conf.mount(force: true)

      # Load AppArmor profile
      ct.apparmor.setup

      # Configure CGroups
      ret = call_cmd(
        Commands::Container::CGParamApply,
        id: ct.id,
        pool: ct.pool.name,
        manipulation_lock: 'ignore',
      )
      return ret unless ret[:status]

      # Enable ksoftlimd
      if CGroup.v1?
        CGroup.set_param(
          File.join(
            CGroup.abs_cgroup_path('memory', ct.base_cgroup_path),
            'memory.ksoftlimd_control'
          ),
          ['1'],
        )
      end

      # Configure devices cgroup
      ct.devices.apply

      # Prepared shared mount directory
      ct.mounts.shared_dir.create

      # Setup start menu
      ct.setup_start_menu

      # User-defined hook
      Hook.run(ct, :pre_start)

      ok

    rescue HookFailed => e
      error(e.message)
    end
  end
end
