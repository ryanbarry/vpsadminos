lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'svctl/version'

Gem::Specification.new do |s|
  s.name = 'svctl'

  s.version = if ENV['OS_BUILD_ID']
                "#{SvCtl::VERSION}.build#{ENV['OS_BUILD_ID']}"
              else
                SvCtl::VERSION
              end

  s.summary     =
    s.description = 'runit service and runlevel manager'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.files      += Dir['man/man?/*.?']
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'MIT'

  s.required_ruby_version = ">= #{File.read('../.ruby-version').strip}"

  s.add_dependency 'filelock'
  s.add_dependency 'gli', '~> 2.20.0'
  s.add_dependency 'libosctl', s.version
end
