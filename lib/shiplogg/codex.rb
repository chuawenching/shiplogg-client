require "json"
require "fileutils"

module Shiplogg
  # The personal Codex plugin marketplace at ~/.agents/plugins/marketplace.json.
  # `shiplogg init --agent codex` adds one entry to it that points Codex at the
  # plugin in this repo, so the user can install it from /plugins. The file is
  # created when missing; other entries in it are left alone.
  class Codex
    MARKETPLACE_NAME = "personal".freeze
    RELATIVE_PATH = File.join(".agents", "plugins", "marketplace.json").freeze
    ENTRY = {
      "name" => "shiplogg",
      "source" => {
        "source" => "git-subdir",
        "url" => "https://github.com/chuawenching/shiplogg-client.git",
        "path" => "./plugins/shiplogg-codex",
        "ref" => "main"
      },
      "policy" => { "installation" => "AVAILABLE", "authentication" => "ON_INSTALL" },
      "category" => "Developer Tools"
    }.freeze

    attr_reader :home

    def initialize(home: Dir.home)
      @home = home
    end

    def path
      File.join(home, RELATIVE_PATH)
    end

    # Returns :added, :updated or :unchanged.
    def register
      doc = read
      plugins = doc["plugins"]
      existing = plugins.find { |p| p.is_a?(Hash) && p["name"] == ENTRY["name"] }

      status = if existing.nil?
        plugins << ENTRY.dup
        :added
      elsif existing == ENTRY
        :unchanged
      else
        plugins[plugins.index(existing)] = ENTRY.dup
        :updated
      end

      write(doc) unless status == :unchanged
      status
    end

    private
      def read
        return fresh unless File.exist?(path)

        doc = JSON.parse(File.read(path))
        raise Error, "#{path} is not a marketplace file (expected a JSON object)" unless doc.is_a?(Hash)
        doc["plugins"] = [] unless doc["plugins"].is_a?(Array)
        doc
      rescue JSON::ParserError => e
        raise Error, "#{path} is not valid JSON (#{e.message}); fix or remove it and run again"
      end

      def fresh
        { "name" => MARKETPLACE_NAME, "interface" => { "displayName" => "Personal plugins" }, "plugins" => [] }
      end

      def write(doc)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(doc) + "\n")
      end
  end
end
