require "test_helper"

class AntigravityTest < Minitest::Test
  def test_creates_the_config_with_a_literal_bearer_token_and_mode_600
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      assert_equal :added, ag.register_mcp("slg_secret")

      path = File.join(home, ".gemini", "config", "mcp_config.json")
      doc = JSON.parse(File.read(path))
      assert_equal({ "serverUrl" => "https://shiplogg.com/mcp", "headers" => { "Authorization" => "Bearer slg_secret" } },
                   doc.dig("mcpServers", "shiplogg"))
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_register_mcp_is_idempotent
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      ag.register_mcp("slg_secret")
      before = File.read(ag.config_path)
      assert_equal :unchanged, ag.register_mcp("slg_secret")
      assert_equal before, File.read(ag.config_path)
    end
  end

  def test_register_mcp_updates_our_entry_and_leaves_others_alone
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      FileUtils.mkdir_p(File.dirname(ag.config_path))
      File.write(ag.config_path, JSON.generate(
        "mcpServers" => {
          "stitch" => { "serverUrl" => "https://stitch.example/mcp", "headers" => { "X-Key" => "k" } },
          "shiplogg" => { "serverUrl" => "https://old.example/mcp" }
        },
        "other" => true
      ))
      File.chmod(0o644, ag.config_path)

      assert_equal :updated, ag.register_mcp("slg_new")

      doc = JSON.parse(File.read(ag.config_path))
      assert_equal true, doc["other"]
      assert_equal %w[stitch shiplogg], doc["mcpServers"].keys
      assert_equal "k", doc.dig("mcpServers", "stitch", "headers", "X-Key")
      assert_equal "Bearer slg_new", doc.dig("mcpServers", "shiplogg", "headers", "Authorization")
      assert_equal 0o600, File.stat(ag.config_path).mode & 0o777
    end
  end

  def test_register_mcp_uses_the_configured_url
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home, url: "http://localhost:3000/")
      ag.register_mcp("slg_x")
      assert_equal "http://localhost:3000/mcp", JSON.parse(File.read(ag.config_path)).dig("mcpServers", "shiplogg", "serverUrl")
    end
  end

  def test_register_mcp_treats_an_empty_file_as_fresh_and_refuses_broken_json
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      FileUtils.mkdir_p(File.dirname(ag.config_path))
      File.write(ag.config_path, "")
      assert_equal :added, ag.register_mcp("slg_x")

      File.write(ag.config_path, "{ not json")
      error = assert_raises(Shiplogg::Error) { ag.register_mcp("slg_x") }
      assert_includes error.message, "not valid JSON"
      assert_equal "{ not json", File.read(ag.config_path)
    end
  end

  def test_register_mcp_requires_a_token
    Dir.mktmpdir do |home|
      assert_raises(Shiplogg::Error) { Shiplogg::Antigravity.new(home: home).register_mcp(" ") }
    end
  end

  def test_install_skill_writes_the_bundled_skill_into_the_shared_skills_dir
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      assert_equal :installed, ag.install_skill

      path = File.join(home, ".gemini", "config", "skills", "shiplogg", "SKILL.md")
      content = File.read(path)
      assert content.start_with?("---\nname: shiplogg\n")
      assert_includes content, 'actor:        "gemini"'
      assert_includes content, Shiplogg::Antigravity::TRAILER
      assert_equal :unchanged, ag.install_skill

      File.write(path, "stale")
      assert_equal :updated, ag.install_skill
      assert_equal content, File.read(path)
    end
  end

  def test_install_rule_creates_the_global_rules_file
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      assert_equal :installed, ag.install_rule
      content = File.read(File.join(home, ".gemini", "GEMINI.md"))
      assert content.start_with?("<!-- shiplogg:start -->\n")
      assert content.end_with?("<!-- shiplogg:end -->\n")
      assert_includes content, Shiplogg::Antigravity::TRAILER
      assert_equal :unchanged, ag.install_rule
    end
  end

  def test_install_rule_appends_to_existing_rules_and_replaces_a_stale_block
    Dir.mktmpdir do |home|
      ag = Shiplogg::Antigravity.new(home: home)
      FileUtils.mkdir_p(File.dirname(ag.rules_path))
      File.write(ag.rules_path, "# My rules\n\nUse tabs.")
      assert_equal :installed, ag.install_rule
      content = File.read(ag.rules_path)
      assert content.start_with?("# My rules\n\nUse tabs.\n\n<!-- shiplogg:start -->")

      File.write(ag.rules_path, content.sub("End every commit", "STALE") + "\n# After\n")
      assert_equal :updated, ag.install_rule
      content = File.read(ag.rules_path)
      assert content.start_with?("# My rules\n\nUse tabs.\n\n<!-- shiplogg:start -->")
      assert content.end_with?("<!-- shiplogg:end -->\n\n# After\n")
      refute_includes content, "STALE"
      assert_equal 1, content.scan("<!-- shiplogg:start -->").size
    end
  end

  # --- through the CLI -------------------------------------------------------

  def test_init_agent_antigravity_writes_both_and_warns_about_the_secret
    Dir.mktmpdir do |home|
      with_git_repo do |root|
        code, out, err = run_cli(["init", "--agent", "antigravity"], env: { "HOME" => home, "SHIPLOGG_TOKEN" => "slg_secret" }, root: root)
        assert_equal 0, code, err
        assert_includes out, "Using token from SHIPLOGG_TOKEN."
        assert_includes out, "Added the shiplogg MCP server to #{home}/.gemini/config/mcp_config.json"
        assert_includes out, "contains your token in clear text"
        assert_includes out, "Installed the shiplogg skill at #{home}/.gemini/config/skills/shiplogg/SKILL.md"
        assert_includes out, "Added the commit-attribution rule to #{home}/.gemini/GEMINI.md"
        assert_includes out, "Co-Authored-By: Antigravity <noreply@google.com>"
        refute_includes out, "slg_secret"
        assert File.exist?(File.join(home, ".gemini", "config", "mcp_config.json"))
      end
    end
  end

  def test_init_agent_antigravity_prompts_for_a_missing_token
    Dir.mktmpdir do |home|
      with_git_repo do |root|
        code, out, = run_cli(["init", "--agent", "antigravity"], env: { "HOME" => home }, root: root, input: "slg_typed\n")
        assert_equal 0, code
        assert_includes out, "shiplogg API token"
        doc = JSON.parse(File.read(File.join(home, ".gemini", "config", "mcp_config.json")))
        assert_equal "Bearer slg_typed", doc.dig("mcpServers", "shiplogg", "headers", "Authorization")

        code, _, err = run_cli(["init", "--agent", "antigravity"], env: { "HOME" => Dir.mktmpdir }, root: root, input: "\n")
        assert_equal 1, code
        assert_includes err, "no token given"
      end
    end
  end

  def test_disclose_antigravity_installs_the_skill_and_rule_but_not_the_mcp_entry
    Dir.mktmpdir do |home|
      code, out, err = run_cli(["disclose", "antigravity"], env: { "HOME" => home })
      assert_equal 0, code, err
      assert_includes out, "Installed the shiplogg skill at"
      assert_includes out, "Added the commit-attribution rule to"
      assert File.exist?(File.join(home, ".gemini", "config", "skills", "shiplogg", "SKILL.md"))
      assert_includes File.read(File.join(home, ".gemini", "GEMINI.md")), Shiplogg::Antigravity::TRAILER
      refute File.exist?(File.join(home, ".gemini", "config", "mcp_config.json"))
    end
  end

  def test_disclose_rejects_unknown_or_missing_agent
    code, _, err = run_cli(["disclose"], env: { "HOME" => Dir.mktmpdir })
    assert_equal 1, code
    assert_includes err, "which agent?"

    code, _, err = run_cli(["disclose", "cursor"], env: { "HOME" => Dir.mktmpdir })
    assert_equal 1, code
    assert_includes err, "unknown agent 'cursor'"
  end

  def test_log_accepts_gemini
    transport = FakeTransport.new(response(201, ENTRY))
    code, = run_cli(["log", "shipped it", "--by", "gemini"], client: client_with(transport))
    assert_equal 0, code
    assert_equal "gemini", transport.last.json["actor"]
  end
end
