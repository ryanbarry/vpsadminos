require 'json'
require 'libosctl'
require 'osctl/template/cli/command'

module OsCtl::Template
  class Cli::Template < Cli::Command
    FIELDS = %i(name distribution version arch vendor variant)

    def list
      if opts[:list]
        puts FIELDS.join("\n")
        return
      end

      tpls = template_list.map do |tpl|
        tpl.load_config

        {
          name: tpl.name,
          distribution: tpl.distribution,
          version: tpl.version,
          arch: tpl.arch,
          vendor: tpl.vendor,
          variant: tpl.variant,
        }
      end

      fmt_opts = {
        layout: :columns,
        sort: opts[:sort] && opts[:sort].split(',').map(&:to_sym),
        header: !opts['hide-header'],
      }

      cols = opts[:output] ? opts[:output].split(',').map(&:to_sym) : FIELDS

      OsCtl::Lib::Cli::OutputFormatter.print(tpls, cols, fmt_opts)
    end

    def build
      require_args!('template')

      templates = template_list

      if args[0] != 'all'
        templates.select! { |tpl| args.include?(tpl.name) }
      end

      templates.each do |tpl|
        Operations::Template::Build.run(
          File.absolute_path('.'),
          tpl,
          output_dir: opts['output-dir'],
          build_dataset: opts['build-dataset'],
          vendor: opts[:vendor],
        )
      end
    end

    def test
      require_args!('template')

      tpl = TemplateList.new('.').detect { |t| t.name == args[0] }
      fail "template '#{args[0]}' not found" unless tpl

      tests = TestList.new('.')

      if args.length > 1 && args[1] != 'all'
        tests.select! { |test| args[1..-1].include?(test.name) }
      end

      results = Operations::Test::Template.run(
        File.absolute_path('.'),
        tpl,
        tests,
        output_dir: opts['output-dir'],
        build_dataset: opts['build-dataset'],
        vendor: opts[:vendor],
        rebuild: opts[:rebuild],
      )

      succeded = results.select { |t| t.success? }
      failed = results.reject { |t| t.success? }

      puts "#{results.length} tests run, #{succeded.length} succeeded, "+
           "#{failed.length} failed"
      return if failed.length == 0

      puts
      puts "Failed tests:"

      failed.each_with_index do |st, i|
        puts "#{i+1}) Test #{st.test} on #{st.template}:"
        puts "  Exit status: #{st.exitstatus}"
        puts "  Output:"
        st.output.split("\n").each { |line| puts (' '*4)+line }
        puts
      end
    end

    protected
    def template_list
      TemplateList.new('.')
    end
  end
end
