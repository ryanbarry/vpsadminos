require 'vpsadminos-converter/net_interface/base'

module VpsAdminOS::Converter
  class NetInterface::Routed < NetInterface::Base
    type :routed

    attr_accessor :via, :routes

    def dump
      super.merge(
        'via' => Hash[via.map do |ip_v, net|
          [
            "v#{ip_v}",
            Hash[ net.map { |k, v| [k.to_s, v.nil? ? v : v.to_string] } ]
          ]
        end],
        'routes' => Hash[routes.map do |ip_v, addrs|
          ["v#{ip_v}", addrs.map(&:to_string)]
        end],
      )
    end
  end
end
