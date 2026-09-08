require "optparse"
require "io/console"

module Shiplogg
  # Argument parsing and the four commands. Everything that touches the
  # terminal or the network is injectable so tests can drive it with arrays
  # and StringIO.
  class CLI
    USAGE = <<~TEXT
      usage: shiplogg <command> [options]

        init                      set up this repo: token, project, .shiplogg, git hook
        init --agent codex        register the shiplogg plugin with Codex (/plugins)
        init --agent antigravity  MCP server + skill for Antigravity (IDE, CLI, app)
        log "message" [--by ACTOR] [--url URL]
                                  record a ship (default actor: human)
        status                    your stats and public URL
        hook install|uninstall    manage the post-commit hook
        disclose antigravity      install the commit-attribution rule and skill for an agent

      actors: #{ACTORS.join(', ')}
      env:    SHIPLOGG_TOKEN, SHIPLOGG_PROJECT, SHIPLOGG_URL
    TEXT

    def self.run(argv, **kwargs)
      new(**kwargs).run(argv)
    end

    def initialize(out: $stdout, err: $stderr, input: $stdin, env: ENV, root: nil, client: nil)
      @out = out
      @err = err
      @input = input
      @env = env
      @root = root
      @client_override = client
    end

    # Returns the process exit code.
    def run(argv)
      argv = argv.dup
      command = argv.shift

      case command
      when "init"           then init(argv)
      when "log"            then log(argv)
      when "status"         then status(argv)
      when "hook"           then hook(argv)
      when "disclose"       then disclose(argv)
      when "version", "--version", "-v"
        @out.puts "shiplogg #{VERSION}"
        0
      when nil, "help", "--help", "-h"
        @out.puts USAGE
        command.nil? ? 1 : 0
      else
        fail!("unknown command '#{command}'\n\n#{USAGE}")
      end
    rescue Error => e
      fail!(e.message)
    rescue OptionParser::ParseError => e
      fail!(e.message)
    end

    private
      # --- commands -----------------------------------------------------------

      def init(argv)
        agent = nil
        OptionParser.new do |o|
          o.banner = "usage: shiplogg init [--agent codex|antigravity]"
          o.on("--agent AGENT", "register the plugin with an agent instead (codex, antigravity)") { |v| agent = v }
        end.parse!(argv)

        case agent
        when nil           then init_repo
        when "codex"       then init_codex
        when "antigravity" then init_antigravity
        else return fail!("unknown agent '#{agent}'; supported: codex, antigravity")
        end
      end

      def init_repo
        token = config.token
        if token.nil?
          token = prompt_secret("shiplogg API token (from your dashboard): ")
          fail!("no token given") if token.empty?
          return 1 if token.empty?
        else
          @out.puts "Using token from #{@env["SHIPLOGG_TOKEN"] ? "SHIPLOGG_TOKEN" : Config::FILE}."
        end

        me = client(token: token).me
        projects = Array(me["projects"])
        fail!("your account has no projects yet; create one on #{config.url} first") if projects.empty?
        return 1 if projects.empty?

        slug = choose_project(projects)

        config.write(token: token, project: slug)
        @out.puts "Wrote #{Config::FILE} (token, project=#{slug})."
        @out.puts "Added #{Config::FILE} to .gitignore." if config.ensure_gitignored

        report_hook_install(hook_for_root.install)
        @out.puts "Logging as @#{me["handle"]} to #{me["log_url"]}"
        0
      end

      def init_codex
        codex = Codex.new(home: @env["HOME"] || Dir.home)
        case codex.register
        when :added     then @out.puts "Added shiplogg to #{codex.path}"
        when :updated   then @out.puts "Updated the shiplogg entry in #{codex.path}"
        when :unchanged then @out.puts "shiplogg is already in #{codex.path}"
        end
        @out.puts
        @out.puts "Next, in Codex:"
        @out.puts "  1. export SHIPLOGG_TOKEN=slg_...   (a token from your shiplogg dashboard)" unless config.token
        @out.puts "  #{config.token ? 1 : 2}. run /plugins, open Personal plugins, install shiplogg"
        @out.puts "     (or: codex plugin add shiplogg@#{Codex::MARKETPLACE_NAME})"
        0
      end

      def init_antigravity
        token = config.token
        if token.nil?
          token = prompt_secret("shiplogg API token (from your dashboard): ")
          return fail!("no token given") if token.empty?
        else
          @out.puts "Using token from #{@env["SHIPLOGG_TOKEN"] ? "SHIPLOGG_TOKEN" : Config::FILE}."
        end

        ag = antigravity
        case ag.register_mcp(token)
        when :added     then @out.puts "Added the shiplogg MCP server to #{ag.config_path}"
        when :updated   then @out.puts "Updated the shiplogg MCP server in #{ag.config_path}"
        when :unchanged then @out.puts "The shiplogg MCP server is already in #{ag.config_path}"
        end
        @out.puts "  That file now contains your token in clear text (Antigravity does not"
        @out.puts "  read environment variables here). Its permissions are set to 600."

        report_skill_install(ag)
        @out.puts
        @out.puts "Restart Antigravity (or run /mcp in the CLI) and the shiplogg tools appear."
        0
      end

      def disclose(argv)
        OptionParser.new { |o| o.banner = "usage: shiplogg disclose antigravity" }.parse!(argv)
        agent = argv.shift
        case agent
        when "antigravity"
          report_skill_install(antigravity)
          0
        when nil then fail!("which agent? usage: shiplogg disclose antigravity")
        else fail!("unknown agent '#{agent}'; supported: antigravity")
        end
      end

      def report_skill_install(ag)
        case ag.install_skill
        when :installed then @out.puts "Installed the shiplogg skill at #{ag.skill_path}"
        when :updated   then @out.puts "Updated the shiplogg skill at #{ag.skill_path}"
        when :unchanged then @out.puts "The shiplogg skill is already at #{ag.skill_path}"
        end
        case ag.install_rule
        when :installed then @out.puts "Added the commit-attribution rule to #{ag.rules_path}"
        when :updated   then @out.puts "Updated the commit-attribution rule in #{ag.rules_path}"
        when :unchanged then @out.puts "The commit-attribution rule is already in #{ag.rules_path}"
        end
        @out.puts "  It tells Antigravity to end every commit with"
        @out.puts "  #{Antigravity::TRAILER}"
      end

      def log(argv)
        actor = "human"
        url = nil
        parser = OptionParser.new do |o|
          o.banner = 'usage: shiplogg log "message" [--by ACTOR] [--url URL]'
          o.on("--by ACTOR", "who shipped it (default: human)") { |v| actor = v }
          o.on("--url URL", "link to the commit, PR or deploy") { |v| url = v }
        end
        parser.parse!(argv)

        body = argv.join(" ").strip
        return fail!("nothing to log; give a message: shiplogg log \"shipped the landing page\"") if body.empty?
        return fail!("unknown actor '#{actor}'; one of: #{ACTORS.join(', ')}") unless ACTORS.include?(actor)
        return fail!("--url must start with http:// or https://") if url && url !~ %r{\Ahttps?://}i

        result = client.create_entry(body: body, actor: actor, url: url, project: config.project)
        entry = result["entry"] || {}
        @out.puts "Logged: #{entry["body"] || body} (#{entry["actor"] || actor})"
        @out.puts result["log_url"] if result["log_url"]
        0
      end

      def status(argv)
        OptionParser.new { |o| o.banner = "usage: shiplogg status" }.parse!(argv)

        me = client.me
        stats = me["stats"] || {}

        @out.puts "@#{me["handle"]}  #{me["log_url"]}"
        @out.puts "ships:   #{stats["total_entries"] || 0}"
        @out.puts "streak:  #{stats["current_streak"] || 0} days (longest #{stats["longest_streak"] || 0})"
        @out.puts "split:   #{format_split(stats["split"])}  (self-reported)" if stats["split"]
        @out.puts "verified: #{format_split(stats["verified_split"])}" if stats["verified_split"]
        0
      end

      def hook(argv)
        action = argv.shift
        case action
        when "install"   then report_hook_install(hook_for_root.install)
        when "uninstall"
          case hook_for_root.uninstall
          when :removed then @out.puts "Removed #{hook_for_root.path}"
          when :absent  then @out.puts "No hook installed at #{hook_for_root.path}"
          when :foreign then return fail!("#{hook_for_root.path} was not installed by shiplogg; not touching it")
          end
        else
          return fail!("usage: shiplogg hook install|uninstall")
        end
        0
      end

      # --- helpers ------------------------------------------------------------

      def report_hook_install(status)
        case status
        when :installed then @out.puts "Installed post-commit hook at #{hook_for_root.path}"
        when :updated   then @out.puts "Updated post-commit hook at #{hook_for_root.path}"
        when :unchanged then @out.puts "Post-commit hook already installed at #{hook_for_root.path}"
        when :foreign
          @out.puts "A post-commit hook already exists at #{hook_for_root.path} and it is not ours."
          @out.puts "Add this line to it to record commits:"
          @out.puts "  sh \"#{Hook::SOURCE}\""
        end
      end

      def choose_project(projects)
        return projects.first["slug"] if projects.size == 1

        current = config.project
        @out.puts "Which project?"
        projects.each_with_index do |p, i|
          mark = p["slug"] == current ? " (current)" : ""
          @out.puts "  #{i + 1}. #{p["name"]}  [#{p["slug"]}]#{mark}"
        end
        default = (projects.index { |p| p["slug"] == current } || 0) + 1
        @out.print "Choose [#{default}]: "
        @out.flush
        answer = (@input.gets || "").strip
        answer = default.to_s if answer.empty?
        by_number = answer =~ /\A\d+\z/ && projects[answer.to_i - 1]
        by_slug = projects.find { |p| p["slug"] == answer }
        chosen = by_number || by_slug
        raise Error, "no such project: #{answer}" unless chosen
        chosen["slug"]
      end

      def prompt_secret(label)
        @out.print label
        @out.flush
        line = if @input.respond_to?(:noecho) && @input.respond_to?(:tty?) && @input.tty?
          value = @input.noecho(&:gets)
          @out.puts
          value
        else
          @input.gets
        end
        (line || "").strip
      end

      # "61% claude_code · 39% human", biggest first.
      def format_split(split)
        counts = split.is_a?(Hash) ? (split["counts"] || {}) : {}
        total = counts.values.sum
        return "no ships yet" if total.zero?
        counts.sort_by { |actor, n| [-n, actor] }.map { |actor, n| "#{(100.0 * n / total).round}% #{actor}" }.join(" · ")
      end

      def fail!(message)
        @err.puts "shiplogg: #{message}"
        1
      end

      def root
        @root ||= begin
          out = IO.popen(["git", "rev-parse", "--show-toplevel"], err: File::NULL, &:read)
          $?.success? ? out.strip : Dir.pwd
        rescue SystemCallError
          Dir.pwd
        end
      end

      def config
        @config ||= Config.new(root, env: @env)
      end

      def hook_for_root
        @hook ||= Hook.new(root)
      end

      def antigravity
        @antigravity ||= Antigravity.new(home: @env["HOME"] || Dir.home, url: config.url)
      end

      def client(token: config.token)
        @client_override || Client.new(base_url: config.url, token: token)
      end
  end
end
