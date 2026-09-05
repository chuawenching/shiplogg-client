require "test_helper"

class HookTest < Minitest::Test
  def test_install_update_and_uninstall_lifecycle
    with_git_repo do |dir|
      hook = Shiplogg::Hook.new(dir)
      assert_equal :installed, hook.install
      assert hook.installed?
      assert_equal File.read(Shiplogg::Hook::SOURCE), File.read(hook.path)
      assert_equal :unchanged, hook.install

      File.write(hook.path, "#!/bin/sh\n# shiplogg post-commit hook (old)\necho old\n")
      assert_equal :updated, hook.install

      assert_equal :removed, hook.uninstall
      assert_equal :absent, hook.uninstall
    end
  end

  def test_never_touches_a_foreign_hook
    with_git_repo do |dir|
      hook = Shiplogg::Hook.new(dir)
      FileUtils.mkdir_p(File.dirname(hook.path))
      File.write(hook.path, "#!/bin/sh\nnpx lefthook run post-commit\n")
      assert hook.foreign?
      assert_equal :foreign, hook.install
      assert_equal :foreign, hook.uninstall
      assert_equal "#!/bin/sh\nnpx lefthook run post-commit\n", File.read(hook.path)
    end
  end

  def test_honours_core_hooks_path
    with_git_repo do |dir|
      system("git", "-C", dir, "config", "core.hooksPath", ".githooks", exception: true)
      hook = Shiplogg::Hook.new(dir)
      assert_equal File.join(dir, ".githooks", "post-commit"), hook.path
      assert_equal :installed, hook.install
      assert File.executable?(File.join(dir, ".githooks", "post-commit"))
    end
  end

  def test_outside_a_git_repo
    Dir.mktmpdir do |dir|
      assert_raises(Shiplogg::Error) { Shiplogg::Hook.new(dir).path }
    end
  end
end
