module OsCtld
  class Commands::Pool::List < Commands::Base
    handle :pool_list

    def execute
      ret = []

      DB::Pools.get.each do |pool|
        next if opts[:names] && !opts[:names].include?(pool.name)

        ret << {
          name: pool.name,
          users: DB::Users.get.count { |v| v.pool == pool },
          groups: DB::Groups.get.count { |v| v.pool == pool },
          containers: DB::Containers.get.count { |v| v.pool == pool },
        }
      end

      ok(ret)
    end
  end
end
