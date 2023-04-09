require 'libosctl'

module OsCtld
  SystemCommandFailed = OsCtl::Lib::Exceptions::SystemCommandFailed

  class ConfigError < StandardError
    # @return [Exception, nil] original exception
    attr_reader :original_exception

    def initialize(msg, original_exception = nil)
      super(msg)
      @original_exception = original_exception
    end
  end

  class CommandFailed < StandardError ; end
  class GroupNotFound < StandardError ; end
  class CGroupSubsystemNotFound < StandardError ; end
  class CGroupParameterNotFound < StandardError ; end

  class CGroupFileNotFound < StandardError
    def initialize(path, value)
      super("Unable to set #{path}=#{value}: parameter not found")
    end
  end

  class ImageNotFound < StandardError ; end
  class ImageRepositoryUnavailable < StandardError ; end

  class DeviceNotAvailable < StandardError
    def initialize(dev, grp)
      super("device '#{dev}' not available in group '#{grp.ident}'")
    end
  end

  class DeviceModeInsufficient < StandardError
    def initialize(dev, grp, mode)
      super("group '#{grp.ident}' provides only mode '#{mode}' for device '#{dev}'")
    end
  end

  class DeviceDescendantRequiresMode < StandardError
    # @param entity [Devices::Owner]
    # @param mode [Devices::Device::Mode]
    def initialize(entity, mode)
      super("#{entity.ident} requires broader device access mode '#{mode}'")
    end
  end

  class DeviceInUse < StandardError ; end

  class DeviceInheritNeeded < DeviceInUse
    # @param entity [Devices::Owner]
    def initialize(entity)
      super("#{entity.ident} would lose access to the device")
    end
  end

  class MountNotFound < StandardError ; end

  class MountInvalid < StandardError ; end

  class UnmountError < StandardError ; end

  class HookFailed < StandardError
    # @param hook [Hook::Base]
    # @param hook_path [String]
    # @param exitstatus [Integer]
    def initialize(hook, hook_path, exitstatus)
      super("hook #{hook.class.hook_name} at #{hook_path} exited with #{exitstatus}")
    end
  end

  class PoolExists < StandardError ; end

  class PoolUpgradeError < StandardError
    attr_reader :pool, :exception

    # @param pool [String]
    # @param exception [Exception]
    def initialize(pool, exception)
      @pool = pool
      @exception = exception

      super("unable to upgrade pool #{pool}: #{exception.message}")
    end
  end

  class DeadlockDetected < StandardError
    def initialize(object, type)
      super("deadlock detected while trying to lock #{object} #{type}ly")
    end
  end

  class ResourceLocked < StandardError
    attr_reader :resource, :holder

    def initialize(resource, holder)
      @resource = resource
      @holder = holder

      resource_ident = ['resource', resource.class.name]
      holder_ident = holder.class.name

      if resource.respond_to?(:manipulation_resource)
        resource_ident = resource.manipulation_resource
      end

      if holder.respond_to?(:manipulation_holder)
        holder_ident = holder.manipulation_holder
      end

      super("#{resource_ident[0]} #{resource_ident[1]} is held by #{holder_ident}")
    end
  end
end
