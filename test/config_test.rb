require "test_helper"

class ConfigTest < Minitest::Test
  def test_parse_handles_spaces_quotes_and_comments
    parsed = Shiplogg::Config.parse(<<~TEXT)
      # comment
      token = "slg_abc"
      project='side'
      project=ignored-second
      junk line
    TEXT
    assert_equal({ "token" => "slg_abc", "project" => "side" }, parsed)
  end

  def test_env_wins_over_file_and_defaults
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".shiplogg"), "token=slg_file\nproject=file\n")
      config = Shiplogg::Config.new(dir, env: { "SHIPLOGG_TOKEN" => "slg_env", "SHIPLOGG_URL" => "http://localhost:3000/" })
      assert_equal "slg_env", config.token
      assert_equal "file", config.project
      assert_equal "http://localhost:3000", config.url

      bare = Shiplogg::Config.new(dir, env: {})
      assert_equal "slg_file", bare.token
      assert_equal "https://shiplogg.com", bare.url

      empty = Shiplogg::Config.new(File.join(dir, "nowhere"), env: {})
      assert_nil empty.token
      assert_nil empty.project
    end
  end

  def test_write_is_mode_600_and_omits_blank_project
    Dir.mktmpdir do |dir|
      config = Shiplogg::Config.new(dir, env: {})
      config.write(token: "slg_x", project: nil)
      assert_equal "token=slg_x\n", File.read(config.path)
      assert_equal 0o600, File.stat(config.path).mode & 0o777
    end
  end

  def test_ensure_gitignored_appends_once_and_respects_missing_newline
    Dir.mktmpdir do |dir|
      config = Shiplogg::Config.new(dir, env: {})
      ignore = File.join(dir, ".gitignore")
      File.write(ignore, "*.gem")
      assert config.ensure_gitignored
      assert_equal "*.gem\n.shiplogg\n", File.read(ignore)
      refute config.ensure_gitignored
      File.write(ignore, "/.shiplogg\n")
      refute config.ensure_gitignored
    end
  end
end
