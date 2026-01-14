# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "claude-task-master"
  spec.version       = "0.2.0"
  spec.authors       = ["Sebastian Vargaciu"]
  spec.email         = ["gore.sebyx@yahoo.com"]

  spec.summary       = "Autonomous task loop for Claude Code"
  spec.description   = <<~DESC
    A lightweight harness that keeps Claude Code working autonomously until
    success criteria are met. Supports any code review system (CodeRabbit,
    GitHub Copilot, etc.) and any CI provider.

    The loop: plan -> work -> check -> work -> check -> done
  DESC
  spec.homepage      = "https://github.com/sebyx07/claude-task-master"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/sebyx07/claude-task-master/issues",
    "changelog_uri" => "https://github.com/sebyx07/claude-task-master/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/sebyx07/claude-task-master",
    "homepage_uri" => "https://github.com/sebyx07/claude-task-master",
    "source_code_uri" => "https://github.com/sebyx07/claude-task-master",
    "rubygems_mfa_required" => "true"
  }

  spec.files         = Dir["lib/**/*", "bin/*", "CLAUDE.md", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.bindir        = "bin"
  spec.executables   = ["claude-task-master"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "faraday-retry", "~> 2.2" # HTTP retry middleware for Octokit
  spec.add_dependency "octokit", "~> 10.0"      # GitHub API client
  spec.add_dependency "pastel", "~> 0.8"        # Terminal colors
  spec.add_dependency "thor", "~> 1.3"          # CLI framework
  spec.add_dependency "tty-spinner", "~> 0.9"   # Progress indicators

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.19"
end
