require "fileutils"

module Shiplogg
  # The .shiplogg file in the repo root, plus the environment that wins over it.
  # Same key=value format the git hook reads: "token=slg_...", "project=my-app".
  class Config
    FILE = ".shiplogg".freeze
    attr_reader :root

    def initialize(root, env: ENV)
      @root = root
      @env = env
    end

    def path
      File.join(root, FILE)
    end

    def token
      first_present(@env["SHIPLOGG_TOKEN"], file_values["token"])
    end

    def project
      first_present(@env["SHIPLOGG_PROJECT"], file_values["project"])
    end

    def url
      first_present(@env["SHIPLOGG_URL"], DEFAULT_URL).sub(%r{/+\z}, "")
    end

    # Rewrites the file with exactly these values. Nil values are omitted.
    def write(token:, project: nil)
      lines = []
      lines << "token=#{token}" if token && !token.empty?
      lines << "project=#{project}" if project && !project.empty?
      File.write(path, lines.map { |l| "#{l}\n" }.join)
      File.chmod(0o600, path)
      path
    end

    # Appends ".shiplogg" to .gitignore unless a line already covers it.
    # Returns true when a line was added.
    def ensure_gitignored
      ignore = File.join(root, ".gitignore")
      existing = File.exist?(ignore) ? File.read(ignore) : ""
      return false if existing.lines.any? { |l| l.strip.sub(%r{\A/}, "") == FILE }

      separator = existing.empty? || existing.end_with?("\n") ? "" : "\n"
      File.write(ignore, "#{existing}#{separator}#{FILE}\n")
      true
    end

    def self.parse(text)
      text.each_line.with_object({}) do |line, hash|
        next unless line =~ /\A\s*([A-Za-z_]+)\s*=\s*(.*?)\s*\z/
        key, value = $1, $2
        value = value[1..-2] if value.length >= 2 && (value.start_with?('"') && value.end_with?('"') || value.start_with?("'") && value.end_with?("'"))
        hash[key] ||= value
      end
    end

    private
      def file_values
        @file_values ||= File.exist?(path) ? self.class.parse(File.read(path)) : {}
      end

      def first_present(*values)
        values.find { |v| v && !v.to_s.strip.empty? }
      end
  end
end
