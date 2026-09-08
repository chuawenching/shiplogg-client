module Shiplogg
  ACTORS = %w[human claude_code grok_build grok_bot openclaw hermes cursor codex gemini other_agent].freeze
  DEFAULT_URL = "https://shiplogg.com".freeze

  class Error < StandardError; end
end

require "shiplogg/version"
require "shiplogg/config"
require "shiplogg/client"
require "shiplogg/hook"
require "shiplogg/codex"
require "shiplogg/antigravity"
require "shiplogg/cli"
