require "fileutils"

module Shiplogg
  # Installs the bundled hooks/post-commit into the repo's hooks directory.
  # Honours core.hooksPath through `git rev-parse --git-path hooks`. A hook we
  # did not write is never touched: install reports it and leaves it alone,
  # uninstall refuses to delete it.
  class Hook
    MARKER = "# shiplogg post-commit hook".freeze
    SOURCE = File.expand_path("../../hooks/post-commit", __dir__)

    attr_reader :root

    def initialize(root)
      @root = root
    end

    def hooks_dir
      out = git("rev-parse", "--git-path", "hooks")
      raise Error, "not a git repository: #{root}" if out.nil?
      File.expand_path(out, root)
    end

    def path
      File.join(hooks_dir, "post-commit")
    end

    def installed?
      File.exist?(path) && ours?(path)
    end

    def foreign?
      File.exist?(path) && !ours?(path)
    end

    # Returns :installed, :updated, :unchanged or :foreign.
    def install
      target = path
      source = File.read(SOURCE)

      if File.exist?(target)
        return :foreign unless ours?(target)
        return :unchanged if File.read(target) == source
        status = :updated
      else
        status = :installed
      end

      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, source)
      File.chmod(0o755, target)
      status
    end

    # Returns :removed, :absent or :foreign.
    def uninstall
      target = path
      return :absent unless File.exist?(target)
      return :foreign unless ours?(target)

      File.delete(target)
      :removed
    end

    private
      def ours?(file)
        File.foreach(file).first(5).any? { |line| line.include?(MARKER) }
      end

      def git(*args)
        out = IO.popen(["git", "-C", root, *args], err: File::NULL, &:read)
        $?.success? ? out.strip : nil
      rescue SystemCallError
        nil
      end
  end
end
