require "test_helper"

class CodexTest < Minitest::Test
  def test_creates_the_personal_marketplace_when_missing
    Dir.mktmpdir do |home|
      codex = Shiplogg::Codex.new(home: home)
      assert_equal :added, codex.register

      doc = JSON.parse(File.read(File.join(home, ".agents", "plugins", "marketplace.json")))
      assert_equal "personal", doc["name"]
      assert_equal 1, doc["plugins"].size
      entry = doc["plugins"].first
      assert_equal "shiplogg", entry["name"]
      assert_equal "git-subdir", entry.dig("source", "source")
      assert_equal "https://github.com/chuawenching/shiplogg-client.git", entry.dig("source", "url")
      assert_equal "./plugins/shiplogg-codex", entry.dig("source", "path")
      assert_equal "main", entry.dig("source", "ref")
      assert_equal "AVAILABLE", entry.dig("policy", "installation")
    end
  end

  def test_is_idempotent
    Dir.mktmpdir do |home|
      codex = Shiplogg::Codex.new(home: home)
      codex.register
      before = File.read(codex.path)
      assert_equal :unchanged, codex.register
      assert_equal before, File.read(codex.path)
    end
  end

  def test_leaves_other_plugins_alone_and_replaces_a_stale_entry
    Dir.mktmpdir do |home|
      codex = Shiplogg::Codex.new(home: home)
      FileUtils.mkdir_p(File.dirname(codex.path))
      File.write(codex.path, JSON.generate(
        "name" => "mine",
        "plugins" => [
          { "name" => "other", "source" => { "source" => "local", "path" => "./plugins/other" } },
          { "name" => "shiplogg", "source" => { "source" => "local", "path" => "./old" } }
        ]
      ))

      assert_equal :updated, codex.register

      doc = JSON.parse(File.read(codex.path))
      assert_equal "mine", doc["name"]
      assert_equal %w[other shiplogg], doc["plugins"].map { |p| p["name"] }
      assert_equal "git-subdir", doc["plugins"].last.dig("source", "source")
    end
  end

  def test_refuses_to_clobber_a_broken_file
    Dir.mktmpdir do |home|
      codex = Shiplogg::Codex.new(home: home)
      FileUtils.mkdir_p(File.dirname(codex.path))
      File.write(codex.path, "{ not json")

      error = assert_raises(Shiplogg::Error) { codex.register }
      assert_includes error.message, "not valid JSON"
      assert_equal "{ not json", File.read(codex.path)
    end
  end
end
