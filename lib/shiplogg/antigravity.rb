require "json"
require "fileutils"

module Shiplogg
  # Antigravity (the IDE, the CLI and the 2.0 app) has no plugin marketplace.
  # It reads one shared config root, ~/.gemini/config/: MCP servers from
  # mcp_config.json and skills from skills/<name>/SKILL.md, plus the global
  # rules file ~/.gemini/GEMINI.md, which is always applied. Three things go
  # in there: the remote MCP entry, with the token written literally because
  # the file has no environment substitution; the shiplogg skill; and the
  # Co-Authored-By rule Antigravity lacks by default. The skill carries the
  # same instruction, but skills load on demand and the rule is what makes a
  # routine commit carry the trailer. Nothing else in those files is touched.
  class Antigravity
    CONFIG_DIR = File.join(".gemini", "config").freeze
    RULES_FILE = File.join(".gemini", "GEMINI.md").freeze
    SERVER_NAME = "shiplogg".freeze
    SKILL_SOURCE = File.expand_path("../../plugins/shiplogg-antigravity/skills/shiplogg/SKILL.md", __dir__)
    TRAILER = "Co-Authored-By: Antigravity <noreply@google.com>".freeze
    RULE_START = "<!-- shiplogg:start -->".freeze
    RULE_END = "<!-- shiplogg:end -->".freeze
    RULE = <<~MD.freeze
      #{RULE_START}
      ## Commit attribution (shiplogg)

      End every commit message you write with the trailer
      `#{TRAILER}`, on its own line after a blank line, as the
      last line of the message. This applies to every commit you author, amend
      or squash, whether or not the user asks for it. Do not add it to commits
      the user writes by hand.
      #{RULE_END}
    MD

    attr_reader :home, :url

    def initialize(home: Dir.home, url: DEFAULT_URL)
      @home = home
      @url = url.sub(%r{/+\z}, "")
    end

    def config_path
      File.join(home, CONFIG_DIR, "mcp_config.json")
    end

    def skill_path
      File.join(home, CONFIG_DIR, "skills", SERVER_NAME, "SKILL.md")
    end

    def rules_path
      File.join(home, RULES_FILE)
    end

    def server_entry(token)
      { "serverUrl" => "#{url}/mcp", "headers" => { "Authorization" => "Bearer #{token}" } }
    end

    # Writes our server into mcp_config.json and makes the file 0600, since it
    # now holds the token. Returns :added, :updated or :unchanged.
    def register_mcp(token)
      raise Error, "no token given" if token.nil? || token.strip.empty?

      doc = read_config
      servers = doc["mcpServers"]
      entry = server_entry(token)

      status = if !servers.key?(SERVER_NAME) then :added
               elsif servers[SERVER_NAME] == entry then :unchanged
               else :updated
               end

      servers[SERVER_NAME] = entry
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, JSON.pretty_generate(doc) + "\n") unless status == :unchanged
      File.chmod(0o600, config_path)
      status
    end

    # Copies the bundled skill into the shared skills directory.
    # Returns :installed, :updated or :unchanged.
    def install_skill
      content = File.read(SKILL_SOURCE)
      existing = File.exist?(skill_path) ? File.read(skill_path) : nil
      return :unchanged if existing == content

      FileUtils.mkdir_p(File.dirname(skill_path))
      File.write(skill_path, content)
      existing.nil? ? :installed : :updated
    end

    # Puts the attribution rule into the global rules file, between markers so
    # it can be replaced later. Everything else in the file is kept as is.
    # Returns :installed, :updated or :unchanged.
    def install_rule
      existing = File.exist?(rules_path) ? File.read(rules_path) : ""
      block = /^#{Regexp.escape(RULE_START)}\n.*?^#{Regexp.escape(RULE_END)}\n?/m

      if existing.match?(block)
        updated = existing.sub(block, RULE)
        return :unchanged if updated == existing
        File.write(rules_path, updated)
        :updated
      else
        FileUtils.mkdir_p(File.dirname(rules_path))
        separator = existing.empty? || existing.end_with?("\n") ? "" : "\n"
        separator += "\n" unless existing.empty? || existing.end_with?("\n\n")
        File.write(rules_path, "#{existing}#{separator}#{RULE}")
        :installed
      end
    end

    private
      def read_config
        return { "mcpServers" => {} } unless File.exist?(config_path) && !File.read(config_path).strip.empty?

        doc = JSON.parse(File.read(config_path))
        raise Error, "#{config_path} is not an MCP config (expected a JSON object)" unless doc.is_a?(Hash)
        doc["mcpServers"] = {} unless doc["mcpServers"].is_a?(Hash)
        doc
      rescue JSON::ParserError => e
        raise Error, "#{config_path} is not valid JSON (#{e.message}); fix or remove it and run again"
      end
  end
end
