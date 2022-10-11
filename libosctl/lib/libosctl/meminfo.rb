module OsCtl::Lib
  class MemInfo
    def initialize(file = '/proc/meminfo')
      @content = File.read(file)
      @values = {}
    end

    def total
      read_param('MemTotal')
    end

    def used(without_cache = true)
      total - free(without_cache)
    end

    def cached
      read_param('Cached')
    end

    def free(without_cache = true)
      v = read_param('MemFree')

      if without_cache
        v + buffers + swap_cached

      else
        v
      end
    end

    def buffers
      read_param('Buffers')
    end

    def swap_total
      read_param('SwapTotal')
    end

    def swap_used
      swap_total - swap_free
    end

    def swap_cached
      read_param('SwapCached')
    end

    def swap_free
      read_param('SwapFree')
    end

    protected
    def read_param(name)
      if @values.has_key?(name)
        @values[name]

      elsif @content =~ /^#{Regexp.escape(name)}:\s*(\d+)\s+kB$/
        @values[name] = $1.to_i

      else
        nil
      end
    end
  end
end
