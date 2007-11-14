module Buildr

  # When running from +rake+, we already have an Application setup and must plug into it,
  # since the top-level tasks come from there. When running from +buildr+, we get to load
  # Rake and set everything up, and we use our own Application full of cool Buildr features.
  if defined?(Rake)
    Rake.application.top_level_tasks.unshift task("buildr:initialize")
  else

    require "rake"

    class Application < Rake::Application #:nodoc:

      DEFAULT_BUILDFILES = ["buildfile", "Buildfile"] + DEFAULT_RAKEFILES

      OPTIONS = [     # :nodoc:
        ['--help',     '-H', GetoptLong::NO_ARGUMENT,
          "Display this help message."],
        ['--nosearch', '-N', GetoptLong::NO_ARGUMENT,
          "Do not search parent directories for the buildfile."],
        ['--quiet',    '-q', GetoptLong::NO_ARGUMENT,
          "Do not log messages to standard output."],
        ['--buildfile', '-f', GetoptLong::REQUIRED_ARGUMENT,
          "Use FILE as the buildfile."],
        ['--require',  '-r', GetoptLong::REQUIRED_ARGUMENT,
          "Require MODULE before executing buildfile."],
        ['--trace',    '-t', GetoptLong::NO_ARGUMENT,
          "Turn on invoke/execute tracing, enable full backtrace."],
        ['--version',  '-V', GetoptLong::NO_ARGUMENT,
          "Display the program version."],
        ['--environment', '-e', GetoptLong::REQUIRED_ARGUMENT,
          "Environment name (e.g. development, test, production)."],
        ['--freeze',   "-F",  GetoptLong::NO_ARGUMENT,
         "Freezes the Buildfile so it always uses Buildr version #{Buildr::VERSION}"],
        ['--unfreeze', "-U",  GetoptLong::NO_ARGUMENT,
         "Unfreezes the Buildfile to use the latest version of Buildr"]
      ]

      def initialize()
        super
        @rakefiles = DEFAULT_BUILDFILES
        @name = "Buildr"
        @requires = []
        opts = GetoptLong.new(*command_line_options)
        opts.each { |opt, value| do_option(opt, value) }
        collect_tasks
        top_level_tasks.unshift "buildr:initialize"
      end

      def run()
        standard_exception_handling do
          find_buildfile
          load_buildfile
          top_level
        end
      end

      def do_option(opt, value)
        case opt
        when '--help'
          help
          exit
        when "--buildfile"
          @rakefiles.clear
          @rakefiles << value
        when '--version'
          puts "Buildr, version #{Buildr::VERSION}"
          exit
        when '--environment'
          ENV['BUILDR_ENV'] = value
        when "--freeze" 
          find_buildfile
          puts "Freezing the Buildfile so it always uses Buildr version #{Buildr::VERSION}"
          original = File.read(rakefile)
          if original =~ /gem\s*(["'])buildr\1/
            modified = original.sub(/gem\s*(["'])buildr\1\s*,\s*(["']).*\2/, %{gem "buildr", "#{Buildr::VERSION}"})
          else
            modified = %{gem "buildr", "#{Buildr::VERSION}"\n} + original
          end
          File.open(rakefile, "w") { |file| file.write modified }
          exit
        when "--unfreeze"
          find_buildfile
          puts "Unfreezing the Buildfile to use the latest version of Buildr from your Gems repository."
          modified = File.read(rakefile).sub(/^\s*gem\s*(["'])buildr\1.*\n/, "")
          File.open(rakefile, "w") { |file| file.write modified }
          exit
        when "--require"
          @requires << value
        when "--nosearch", "--quiet", "--trace"
          super
        end
      end

      def find_buildfile()
        here = Dir.pwd
        while ! have_rakefile
          Dir.chdir("..")
          if Dir.pwd == here || options.nosearch
            error = "No Buildfile found (looking for: #{@rakefiles.join(', ')})"
            if STDIN.isatty
              chdir(original_dir) { task("generate").invoke }
              exit 1
            else
              raise error
            end
          end
          here = Dir.pwd
        end
      end

      def load_buildfile()
        @requires.each { |name| require name }
        puts Buildr.environment ? "(in #{Dir.pwd}, #{Buildr.environment})" : "(in #{Dir.pwd})"
        load File.expand_path(@rakefile) if @rakefile != ''
        load_imports
      end

      def usage()
        puts "Buildr #{Buildr::VERSION}"
        puts
        puts "Usage:"
        puts "  buildr [-f buildfile] {options} targets..."
      end

      def help()
        usage
        puts
        puts "Options:"
        OPTIONS.sort.each do |long, short, mode, desc|
          if mode == GetoptLong::REQUIRED_ARGUMENT
            if desc =~ /\b([A-Z]{2,})\b/
              long = long + "=#{$1}"
            end
          end
          printf "  %-20s (%s)\n", long, short
          printf "      %s\n", desc
        end
        puts
        puts "For help with your buildfile:"
        puts "  buildr help"
      end

      def command_line_options
        OPTIONS.collect { |lst| lst[0..-2] }
      end
    end

    Rake.application = Buildr::Application.new
  end


  class << self

    # Loads buildr.rake files from users home directory and project directory.
    # Loads custom tasks from .rake files in tasks directory.
    def load_tasks_and_local_files() #:nodoc:
      return false if @build_files
      # Load the settings files.
      @build_files = [ File.expand_path("buildr.rb", Gem::user_home), "buildr.rb" ].select { |file| File.exist?(file) }
      @build_files += [ File.expand_path("buildr.rake", Gem::user_home), File.expand_path("buildr.rake") ].
        select { |file| File.exist?(file) }.each { |file| warn "Please use '#{file.ext('rb')}' instead of '#{file}'" }
      #Load local tasks that can be used in the Buildfile.
      @build_files += Dir["#{Dir.pwd}/tasks/*.rake"]
      @build_files.each do |file|
        unless $LOADED_FEATURES.include?(file)
          load file
          $LOADED_FEATURES << file
        end
      end
      true
    end

    # :call-seq:
    #   build_files() => files
    #
    # Returns a list of build files. These are files used by the build, 
    def build_files()
      [Rake.application.rakefile].compact + @build_files
    end

    task "buildr:initialize" do
      Buildr.load_tasks_and_local_files
    end

  end

end