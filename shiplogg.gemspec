require_relative "lib/shiplogg/version"

Gem::Specification.new do |spec|
  spec.name          = "shiplogg"
  spec.version       = Shiplogg::VERSION
  spec.authors       = ["Chua Wen Ching"]
  spec.summary       = "CLI for shiplogg, the ship log for humans and their agents."
  spec.description   = "Records what you ship, and who shipped it, to your public build log at shiplogg.com. Installs the git hook, logs entries by hand, shows your stats."
  spec.homepage      = "https://github.com/chuawenching/shiplogg-client"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri"   => "#{spec.homepage}/commits/main",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }

  spec.files = Dir["lib/**/*.rb", "exe/*", "hooks/post-commit", "plugins/shiplogg-antigravity/skills/shiplogg/SKILL.md", "LICENSE", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = ["shiplogg"]
  spec.require_paths = ["lib"]
end
