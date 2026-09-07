require "test_helper"

class CLITest < Minitest::Test
  def test_no_command_prints_usage_and_fails
    code, out, = run_cli([])
    assert_equal 1, code
    assert_includes out, "usage: shiplogg"
  end

  def test_unknown_command
    code, _, err = run_cli(["frobnicate"])
    assert_equal 1, code
    assert_includes err, "unknown command 'frobnicate'"
  end

  def test_version
    code, out, = run_cli(["version"])
    assert_equal 0, code
    assert_equal "shiplogg #{Shiplogg::VERSION}\n", out
  end

  def test_log_requires_a_message
    transport = FakeTransport.new(response(201, ENTRY))
    code, _, err = run_cli(["log"], client: client_with(transport))
    assert_equal 1, code
    assert_includes err, "nothing to log"
    assert_empty transport.calls
  end

  def test_log_rejects_unknown_actor
    transport = FakeTransport.new(response(201, ENTRY))
    code, _, err = run_cli(["log", "x", "--by", "skynet"], client: client_with(transport))
    assert_equal 1, code
    assert_includes err, "unknown actor 'skynet'"
    assert_includes err, "claude_code"
    assert_empty transport.calls
  end

  def test_log_rejects_non_http_url
    transport = FakeTransport.new(response(201, ENTRY))
    code, _, err = run_cli(["log", "x", "--url", "javascript:alert(1)"], client: client_with(transport))
    assert_equal 1, code
    assert_includes err, "--url must start with http"
    assert_empty transport.calls
  end

  def test_log_unknown_option
    code, _, err = run_cli(["log", "x", "--nope"], client: client_with(FakeTransport.new))
    assert_equal 1, code
    assert_includes err, "invalid option: --nope"
  end

  def test_log_defaults_to_human_and_source_cli
    transport = FakeTransport.new(response(201, ENTRY))
    code, out, = run_cli(["log", "shipped the landing page"], client: client_with(transport))
    assert_equal 0, code
    body = transport.last.json
    assert_equal({ "source" => "cli", "body" => "shipped the landing page", "actor" => "human" }, body)
    assert_includes out, "Logged: shipped it (human)"
    assert_includes out, "https://shiplogg.com/@wen"
  end

  def test_log_with_actor_url_and_project_from_config
    with_git_repo do |dir|
      File.write(File.join(dir, ".shiplogg"), "token=slg_file\nproject=side\n")
      transport = FakeTransport.new(response(201, ENTRY))
      code, = run_cli(["log", "wired", "up", "auth", "--by", "claude_code", "--url", "https://github.com/x/y/pull/1"],
                      client: client_with(transport), root: dir)
      assert_equal 0, code
      body = transport.last.json
      assert_equal "wired up auth", body["body"]
      assert_equal "claude_code", body["actor"]
      assert_equal "https://github.com/x/y/pull/1", body["external_url"]
      assert_equal "side", body["project"]
      assert_equal "cli", body["source"]
    end
  end

  def test_log_env_project_wins_over_file
    with_git_repo do |dir|
      File.write(File.join(dir, ".shiplogg"), "project=side\n")
      transport = FakeTransport.new(response(201, ENTRY))
      run_cli(["log", "x"], client: client_with(transport), root: dir, env: { "SHIPLOGG_PROJECT" => "shiplogg" })
      assert_equal "shiplogg", transport.last.json["project"]
    end
  end

  def test_log_surfaces_server_validation_error
    transport = FakeTransport.new(response(422, { "error" => "Entry is invalid.", "details" => { "body" => ["is too long"] } }))
    code, _, err = run_cli(["log", "x"], client: client_with(transport))
    assert_equal 1, code
    assert_includes err, "Entry is invalid.: body is too long"
  end

  def test_status_prints_stats_and_labels_self_reported_split
    transport = FakeTransport.new(response(200, ME))
    code, out, = run_cli(["status"], client: client_with(transport))
    assert_equal 0, code
    assert_equal "GET", transport.last.request.method
    assert_equal "/api/v1/me", transport.last.uri.path
    assert_includes out, "@wen  https://shiplogg.com/@wen"
    assert_includes out, "ships:   312"
    assert_includes out, "streak:  4 days (longest 12)"
    assert_includes out, "39% human"
    assert_includes out, "61% claude_code"
    assert_includes out, "(self-reported)"
    refute_includes out, "verified:"
  end

  def test_status_shows_verified_split_separately
    me = JSON.parse(JSON.generate(ME))
    me["stats"]["verified_split"] = { "counts" => { "claude_code" => 10, "human" => 10 }, "human_share" => 0.5 }
    transport = FakeTransport.new(response(200, me))
    _, out, = run_cli(["status"], client: client_with(transport))
    assert_includes out, "verified: 50% claude_code · 50% human"
  end

  def test_status_unauthorized
    transport = FakeTransport.new(response(401, { "error" => "Missing or invalid API token." }))
    code, _, err = run_cli(["status"], client: client_with(transport))
    assert_equal 1, code
    assert_includes err, "Missing or invalid API token."
  end

  def test_init_with_env_token_writes_config_ignores_it_and_installs_hook
    with_git_repo do |dir|
      transport = FakeTransport.new(response(200, ME))
      code, out, err = run_cli(["init"], client: client_with(transport), root: dir,
                               env: { "SHIPLOGG_TOKEN" => "slg_env" }, input: "2\n")
      assert_equal 0, code, err
      assert_equal "Bearer slg_test", transport.last.header("Authorization")
      assert_equal "token=slg_env\nproject=side\n", File.read(File.join(dir, ".shiplogg"))
      assert_equal ".shiplogg\n", File.read(File.join(dir, ".gitignore"))
      assert File.executable?(File.join(dir, ".git/hooks/post-commit"))
      assert_includes out, "Installed post-commit hook"
      assert_includes out, "Logging as @wen"
    end
  end

  def test_init_prompts_for_token_when_none_configured
    with_git_repo do |dir|
      transport = FakeTransport.new(response(200, ME))
      code, = run_cli(["init"], client: client_with(transport), root: dir, input: "slg_typed\n1\n")
      assert_equal 0, code
      assert_equal "token=slg_typed\nproject=shiplogg\n", File.read(File.join(dir, ".shiplogg"))
    end
  end

  def test_init_auto_picks_single_project
    with_git_repo do |dir|
      me = ME.merge("projects" => [ME["projects"].first])
      transport = FakeTransport.new(response(200, me))
      code, out, = run_cli(["init"], client: client_with(transport), root: dir, env: { "SHIPLOGG_TOKEN" => "slg_env" })
      assert_equal 0, code
      refute_includes out, "Which project?"
      assert_includes File.read(File.join(dir, ".shiplogg")), "project=shiplogg"
    end
  end

  def test_init_is_idempotent
    with_git_repo do |dir|
      env = { "SHIPLOGG_TOKEN" => "slg_env" }
      2.times { run_cli(["init"], client: client_with(FakeTransport.new(response(200, ME))), root: dir, env: env, input: "1\n") }
      _, out, = run_cli(["init"], client: client_with(FakeTransport.new(response(200, ME))), root: dir, env: env, input: "\n")
      assert_equal ".shiplogg\n", File.read(File.join(dir, ".gitignore"))
      assert_includes out, "already installed"
      assert_includes out, "(current)"
      assert_includes File.read(File.join(dir, ".shiplogg")), "project=shiplogg"
    end
  end

  def test_init_fails_on_bad_token_without_writing
    with_git_repo do |dir|
      transport = FakeTransport.new(response(401, { "error" => "Missing or invalid API token." }))
      code, _, err = run_cli(["init"], client: client_with(transport), root: dir, env: { "SHIPLOGG_TOKEN" => "slg_bad" })
      assert_equal 1, code
      assert_includes err, "Missing or invalid API token."
      refute File.exist?(File.join(dir, ".shiplogg"))
    end
  end

  def test_hook_install_and_uninstall
    with_git_repo do |dir|
      code, out, = run_cli(["hook", "install"], root: dir)
      assert_equal 0, code
      assert_includes out, "Installed"
      code, out, = run_cli(["hook", "uninstall"], root: dir)
      assert_equal 0, code
      assert_includes out, "Removed"
      refute File.exist?(File.join(dir, ".git/hooks/post-commit"))
    end
  end

  def test_hook_bad_action
    code, _, err = run_cli(["hook", "dance"])
    assert_equal 1, code
    assert_includes err, "usage: shiplogg hook install|uninstall"
  end
  def test_init_agent_codex_writes_personal_marketplace_and_prints_next_steps
    Dir.mktmpdir do |home|
      code, out, = run_cli(["init", "--agent", "codex"], env: { "HOME" => home }, client: client_with(FakeTransport.new))
      assert_equal 0, code
      assert File.exist?(File.join(home, ".agents", "plugins", "marketplace.json"))
      assert_includes out, "Added shiplogg to"
      assert_includes out, "export SHIPLOGG_TOKEN"
      assert_includes out, "/plugins"
      assert_includes out, "codex plugin add shiplogg@personal"
    end
  end

  def test_init_agent_codex_skips_token_step_when_token_is_configured
    Dir.mktmpdir do |home|
      code, out, = run_cli(["init", "--agent", "codex"], env: { "HOME" => home, "SHIPLOGG_TOKEN" => "slg_x" }, client: client_with(FakeTransport.new))
      assert_equal 0, code
      refute_includes out, "export SHIPLOGG_TOKEN"
      assert_includes out, "1. run /plugins"
    end
  end

  def test_init_rejects_unknown_agent
    code, _, err = run_cli(["init", "--agent", "skynet"], client: client_with(FakeTransport.new))
    assert_equal 1, code
    assert_includes err, "unknown agent 'skynet'"
  end
end
