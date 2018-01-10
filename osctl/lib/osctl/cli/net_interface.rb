require 'ipaddress'

module OsCtl::Cli
  class NetInterface < Command
    FIELDS = %i(
      name
      index
      type
      link
      veth
      via
      hwaddr
    )

    FILTERS = %i(
      type
      link
    )

    DEFAULT_FIELDS = %i(
      name
      type
      link
      veth
    )

    IP_FIELDS = %i(
      version
      addr
    )

    def list
      if opts[:list]
        puts FIELDS.join("\n")
        return
      end

      raise "missing arguments" unless args[0]

      cmd_opts = {id: args[0]}
      fmt_opts = {layout: :columns}

      FILTERS.each do |v|
        next unless opts[v]
        cmd_opts[v] = opts[v].split(',')
      end

      cmd_opts[:ids] = args if args.count > 0
      fmt_opts[:header] = false if opts['hide-header']

      osctld_fmt(
        :netif_list,
        cmd_opts,
        opts[:output] ? opts[:output].split(',').map(&:to_sym) : DEFAULT_FIELDS,
        fmt_opts
      )
    end

    def create_bridge
      raise "missing arguments" if args.count < 2

      cmd_opts = {
        id: args[0],
        name: args[1],
        type: 'bridge',
        hwaddr: opts[:hwaddr],
        link: opts[:link]
      }

      osctld_fmt(:netif_create, cmd_opts)
    end

    def create_routed
      raise "missing arguments" if args.count < 2

      cmd_opts = {
        id: args[0],
        name: args[1],
        type: 'routed',
        hwaddr: opts[:hwaddr],
        via: parse_route_via
      }

      osctld_fmt(:netif_create, cmd_opts)
    end

    def delete
      raise 'missing container id' unless args[0]
      raise 'missing interface name' unless args[1]
      osctld_fmt(:netif_delete, id: args[0], name: args[1])
    end

    def ip_list
      raise 'missing container id' unless args[0]
      raise 'missing interface name' unless args[1]

      if opts[:list]
        puts IP_FIELDS.join("\n")
        return
      end

      cmd_opts = {id: args[0], name: args[1]}
      fmt_opts = {layout: :columns}

      fmt_opts[:header] = false if opts['hide-header']

      ret = []
      data = osctld_call(:netif_ip_list, cmd_opts)

      data.each do |v, addrs|
        ip_v = v.to_s.to_i
        next if opts[:version] && opts[:version] != ip_v

        addrs.each do |addr|
          ret << {
            version: ip_v,
            addr: addr,
          }
        end
      end

      OutputFormatter.print(
        ret,
        opts[:output] ? opts[:output].split(',').map(&:to_sym) : IP_FIELDS,
        fmt_opts
      )
    end

    def ip_add
      raise 'missing container id' unless args[0]
      raise 'missing interface name' unless args[1]
      raise 'missing addr' unless args[2]
      osctld_fmt(:netif_ip_add, id: args[0], name: args[1], addr: args[2])
    end

    def ip_del
      raise 'missing container id' unless args[0]
      raise 'missing interface name' unless args[1]
      raise 'missing addr' unless args[2]
      osctld_fmt(:netif_ip_del, id: args[0], name: args[1], addr: args[2])
    end

    protected
    def parse_route_via
      ret = {}

      opts[:via].each do |net|
        addr = IPAddress.parse(net)
        ip_v = addr.ipv4? ? 4 : 6

        if ret.has_key?(ip_v)
          fail "network for IPv#{ip_v} has already been set to route via #{ret[ip_v]}"
        end

        case ip_v
        when 4
          if addr.prefix > 30
            fail "cannot route via IPv4 network smaller than /30"
          end

        when 6
          # TODO: check?
        end

        ret[ip_v] = addr.to_string
      end

      ret
    end
  end
end
