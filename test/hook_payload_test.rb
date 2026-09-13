require "test_helper"

# Runs hooks/post-commit against a real git repo with a stub curl first on
# PATH, and inspects the JSON the hook would have posted.
class HookPayloadTest < Minitest::Test
  TRAILER = "Co-Authored-By: Claude <noreply@anthropic.com>".freeze
  SUBJECT = "Add the landing page".freeze
  BODY_PARAGRAPH = "Explains the whole design in prose that must stay local.".freeze

  def test_sends_metadata_and_trailers_only_by_default
    with_committed_repo do |dir|
      json = run_hook(dir)
      sha = git(dir, "rev-parse", "HEAD")

      assert_equal "git_hook", json["source"]
      assert_equal sha, json["external_id"]
      assert_equal "Ada Author", json["author_name"]
      assert_equal "ada@example.com", json["author_email"]
      assert_equal "Cal Committer", json["committer_name"]
      assert_equal "cal@example.com", json["committer_email"]
      assert_equal "cursor/test", json["branch"]
      assert_includes json["commit_message"], TRAILER
      refute_includes json["commit_message"], BODY_PARAGRAPH
      refute_includes json["commit_message"], SUBJECT
      refute json.key?("body"), "body must be absent unless subjects=true"
    end
  end

  def test_sends_the_subject_when_the_repo_opts_in
    with_committed_repo do |dir|
      File.write(File.join(dir, ".shiplogg"), "subjects = true\n")
      json = run_hook(dir)

      assert_equal SUBJECT, json["body"]
      refute_includes json["commit_message"], BODY_PARAGRAPH
    end
  end

  def test_omits_branch_on_a_detached_head
    with_committed_repo do |dir|
      git(dir, "checkout", "-q", "--detach")
      json = run_hook(dir)

      refute json.key?("branch"), "branch must be absent on a detached HEAD"
      assert_includes json["commit_message"], TRAILER
    end
  end

  private

  def with_committed_repo
    with_git_repo do |dir|
      git(dir, "checkout", "-q", "-b", "cursor/test")
      File.write(File.join(dir, "index.html"), "<h1>hi</h1>\n")
      git(dir, "add", "index.html")
      message = "#{SUBJECT}\n\n#{BODY_PARAGRAPH}\n\n#{TRAILER}\n"
      git(dir, "commit", "-q", "-m", message,
          env: { "GIT_AUTHOR_NAME" => "Ada Author", "GIT_AUTHOR_EMAIL" => "ada@example.com",
                 "GIT_COMMITTER_NAME" => "Cal Committer", "GIT_COMMITTER_EMAIL" => "cal@example.com" })
      yield dir
    end
  end

  # Runs the hook with a stub curl that writes its stdin to a capture file,
  # waits for the backgrounded curl to finish, and returns the parsed JSON.
  def run_hook(dir)
    Dir.mktmpdir("shiplogg-bin") do |bin|
      capture = File.join(bin, "payload.json")
      stub = File.join(bin, "curl")
      File.write(stub, "#!/bin/sh\ncat > \"$SHIPLOGG_TEST_CAPTURE.tmp\" && mv \"$SHIPLOGG_TEST_CAPTURE.tmp\" \"$SHIPLOGG_TEST_CAPTURE\"\nprintf 200\n")
      File.chmod(0o755, stub)

      env = {
        "PATH" => "#{bin}:#{ENV["PATH"]}",
        "SHIPLOGG_TOKEN" => "slg_test",
        "SHIPLOGG_TEST_CAPTURE" => capture,
        "SHIPLOGG_PROJECT" => nil,
        "SHIPLOGG_SUBJECTS" => nil,
        "SHIPLOGG_URL" => "http://127.0.0.1:9"
      }
      ok = system(env, "sh", Shiplogg::Hook::SOURCE, chdir: dir)
      assert ok, "hook must exit 0"

      deadline = Time.now + 5
      sleep 0.05 until File.exist?(capture) || Time.now > deadline
      assert File.exist?(capture), "stub curl never received a payload"

      JSON.parse(File.read(capture))
    end
  end

  def git(dir, *args, env: {})
    out = IO.popen(env, ["git", "-C", dir, *args], &:read)
    raise "git #{args.join(' ')} failed" unless $?.success?
    out.strip
  end
end
