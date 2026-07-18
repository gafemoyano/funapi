# frozen_string_literal: true

require "optparse"
require "rbconfig"
require_relative "version"

module FunApi
  class CLI
    def self.start(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      original = argv.dup
      command = argv.shift

      case command
      when "new"
        Commands::New.new(argv).run
      when "dev", "server", "serve"
        Commands::Dev.new(argv, original_argv: original).run
      when "routes"
        Commands::Routes.new(argv).run
      when "version", "-v", "--version"
        puts "funapi #{FunApi::VERSION}"
        0
      when nil, "help", "-h", "--help"
        print_usage
        0
      else
        warn "funapi: unknown command '#{command}'"
        print_usage
        1
      end
    end

    def print_usage
      puts <<~USAGE
        funapi #{FunApi::VERSION}

        Usage: funapi <command> [options]

        Commands:
          new NAME              Scaffold a new FunApi application
          dev [--port] [--bind] Boot the app under Falcon with code reloading
          routes [--json]       Print the route table
          version               Print the FunApi version

        Run 'funapi <command> --help' for command-specific options.
      USAGE
    end

    module Loader
      def load_app(dir = Dir.pwd)
        require "funapi"

        ru = File.join(dir, "config.ru")
        app_rb = File.join(dir, "app.rb")

        if File.exist?(ru)
          require "rack"
          built = Rack::Builder.parse_file(ru)
          built = built.first if built.is_a?(Array)
          unwrap(built)
        elsif File.exist?(app_rb)
          require app_rb
          find_app
        else
          raise "No config.ru or app.rb found in #{dir}"
        end
      end

      def unwrap(app)
        current = app
        seen = 0
        while current && !current.is_a?(FunApi::App) && seen < 25
          current = current.instance_variable_get(:@app)
          seen += 1
        end
        current.is_a?(FunApi::App) ? current : find_app
      end

      def find_app
        if Object.const_defined?(:Application) && Object.const_get(:Application).is_a?(FunApi::App)
          return Object.const_get(:Application)
        end

        instance = ObjectSpace.each_object(FunApi::App).first
        raise "Could not locate a FunApi::App instance (expected an 'Application' constant)" unless instance
        instance
      end
    end

    class Reloader
      IGNORED_DIRS = %w[vendor .git tmp node_modules .bundle log coverage].freeze

      def initialize(dir:, extensions: %w[.rb .ru], interval: 1.0, debounce: 0.2)
        @dir = dir
        @extensions = extensions
        @interval = interval
        @debounce = debounce
      end

      def scan
        snapshot = {}
        Dir.glob(File.join(@dir, "**", "*")).each do |path|
          next if ignored?(path)
          next unless watched?(path)
          next unless File.file?(path)

          snapshot[path] = begin
            File.mtime(path).to_f
          rescue
            nil
          end
        end
        snapshot
      end

      def changed?(previous)
        previous != scan
      end

      def watch
        previous = scan
        loop do
          sleep(@interval)
          next unless changed?(previous)

          sleep(@debounce)
          yield
          previous = scan
        end
      end

      private

      def watched?(path)
        @extensions.include?(File.extname(path))
      end

      def ignored?(path)
        relative = path.delete_prefix(@dir).sub(%r{\A/}, "")
        segments = relative.split("/")
        segments.any? { |segment| IGNORED_DIRS.include?(segment) }
      end
    end

    module Commands
      class New
        def initialize(argv)
          @argv = argv
        end

        def run
          parse!
          return 1 unless @name

          target = File.expand_path(@name)

          if File.directory?(target) && !Dir.empty?(target)
            warn "funapi: refusing to overwrite non-empty directory '#{@name}'"
            return 1
          end

          app_title = File.basename(@name)
          require_relative "cli/templates"
          Templates.write_all(target, app_title)

          puts "Created #{@name}/"
          puts <<~NEXT

            Next steps:
              cd #{@name}
              bundle install
              funapi dev        # then open http://localhost:3000/docs
          NEXT
          0
        end

        private

        def parse!
          parser = OptionParser.new do |opts|
            opts.banner = "Usage: funapi new NAME"
          end
          rest = parser.parse(@argv)
          @name = rest.first

          unless @name
            warn "funapi new: NAME is required"
            puts parser
          end
        end
      end

      class Routes
        include Loader

        def initialize(argv)
          @argv = argv
          @json = false
        end

        def run
          parse!
          app = load_app
          routes = app.routes

          if @json
            require "json"
            puts JSON.pretty_generate(routes)
          else
            print_table(routes)
          end
          0
        rescue => e
          warn "funapi routes: #{e.message}"
          1
        end

        private

        def parse!
          OptionParser.new do |opts|
            opts.banner = "Usage: funapi routes [--json]"
            opts.on("--json", "Emit machine-readable JSON") { @json = true }
          end.parse!(@argv)
        end

        def print_table(routes)
          if routes.empty?
            puts "No routes defined."
            return
          end

          rows = routes.map do |route|
            [
              route[:websocket] ? "WS" : route[:verb],
              route[:path],
              Array(route[:tags]).join(","),
              schemas_summary(route)
            ]
          end

          headers = %w[VERB PATH TAGS SCHEMAS]
          widths = headers.each_index.map do |i|
            ([headers[i]] + rows.map { |r| r[i].to_s }).map(&:length).max
          end

          puts format_row(headers, widths)
          rows.each { |row| puts format_row(row, widths) }
        end

        def schemas_summary(route)
          parts = []
          parts << "path=#{route[:path_schema]}" if route[:path_schema]
          parts << "query=#{route[:query_schema]}" if route[:query_schema]
          parts << "body=#{route[:body_schema]}" if route[:body_schema]
          parts << "response=#{route[:response_schema]}" if route[:response_schema]
          parts.empty? ? "-" : parts.join(" ")
        end

        def format_row(cells, widths)
          cells.each_index.map { |i| cells[i].to_s.ljust(widths[i]) }.join("  ").rstrip
        end
      end

      class Dev
        include Loader

        def initialize(argv, original_argv: [])
          @argv = argv
          @original_argv = original_argv
          @port = 3000
          @bind = "localhost"
          @no_reload = false
        end

        def run
          parse!
          $stdout.sync = true
          dir = Dir.pwd

          start_reloader(dir) unless @no_reload

          app = load_app(dir)

          puts "FunApi dev server: http://#{@bind}:#{@port}"
          puts "Interactive docs:  http://#{@bind}:#{@port}/docs"
          puts "Code reloading:    #{@no_reload ? "off" : "on (restarts on file change)"}"
          puts "Press Ctrl+C to stop"

          boot(app)
          0
        rescue => e
          warn "funapi dev: #{e.message}"
          1
        end

        private

        def parse!
          OptionParser.new do |opts|
            opts.banner = "Usage: funapi dev [options]"
            opts.on("--port PORT", Integer, "Port to bind (default 3000)") { |v| @port = v }
            opts.on("--bind HOST", "Host to bind (default localhost)") { |v| @bind = v }
            opts.on("--no-reload", "Disable code reloading") { @no_reload = true }
          end.parse!(@argv)
        end

        def start_reloader(dir)
          reloader = Reloader.new(dir: dir)
          command = [RbConfig.ruby, $PROGRAM_NAME, *@original_argv]

          Thread.new do
            reloader.watch do
              puts "\n[funapi] change detected — restarting..."
              Kernel.exec(*command)
            end
          end
        end

        def boot(app)
          require "falcon"
          require "protocol/rack"
          require "async"
          require "async/http/endpoint"

          ENV["FUNAPI_ENV"] ||= "development"

          %i[INT TERM].each do |signal|
            trap(signal) { exit }
          end

          begin
            Async do |task|
              endpoint = Async::HTTP::Endpoint.parse("http://#{@bind}:#{@port}")
              server = Falcon::Server.new(Protocol::Rack::Adapter.new(app), endpoint)
              app.run_startup_hooks if app.respond_to?(:run_startup_hooks)
              server.run
            end.wait
          rescue Interrupt
            nil
          ensure
            app.run_shutdown_hooks if app.respond_to?(:run_shutdown_hooks)
          end
        end
      end
    end
  end
end
