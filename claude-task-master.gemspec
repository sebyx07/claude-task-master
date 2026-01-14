# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'claude-task-master'
  spec.version       = '0.1.0'
  spec.authors       = ['developerz.ai']
  spec.email         = ['hello@developerz.ai']

  spec.summary       = 'Autonomous task loop for Claude Code'
  spec.description   = <<~DESC
    A lightweight harness that keeps Claude Code working autonomously until
    success criteria are met. Supports any code review system (CodeRabbit,
    GitHub Copilot, etc.) and any CI provider.

    The loop: plan -> work -> check -> work -> check -> done
  DESC
  spec.homepage      = 'https://github.com/developerz-ai/claude-task-master'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.files         = Dir['lib/**/*', 'bin/*', 'CLAUDE.md', 'README.md', 'LICENSE']
  spec.bindir        = 'bin'
  spec.executables   = ['claude-task-master']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'thor', '~> 1.3'        # CLI framework
  spec.add_dependency 'tty-spinner', '~> 0.9' # Progress indicators
  spec.add_dependency 'pastel', '~> 0.8'      # Terminal colors
  spec.add_dependency 'octokit', '~> 10.0'    # GitHub API client

  # Development dependencies
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.60'
end
