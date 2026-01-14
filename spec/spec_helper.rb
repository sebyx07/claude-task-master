# frozen_string_literal: true

require "simplecov"

# Start SimpleCov with proper configuration
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"

  # Group coverage by file type
  add_group "CLI", "lib/claude_task_master/cli.rb"
  add_group "Core", ["lib/claude_task_master/loop.rb", "lib/claude_task_master/state.rb"]
  add_group "Integrations", ["lib/claude_task_master/claude.rb", "lib/claude_task_master/github.rb"]
  add_group "Models", "lib/claude_task_master/pr_comment.rb"

  # Set minimum coverage threshold (aim for 80%+)
  minimum_coverage 80
  minimum_coverage_by_file 70

  # Format output
  formatter SimpleCov::Formatter::HTMLFormatter
end

# Require main library
require "claude_task_master"

# Require all support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

# RSpec configuration
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Use expect syntax (not should)
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure output
  config.color = true
  config.tty = true
  config.formatter = :documentation

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Allow focusing on specific tests
  config.filter_run_when_matching :focus

  # Shared context for temporary directories
  config.include_context "with temp directory", :temp_dir

  # Shared context for mocked GitHub API
  config.include_context "with mocked github api", :github_api

  # Shared context for mocked Claude CLI
  config.include_context "with mocked claude cli", :claude_cli

  # Clean up state directory after each test
  config.after do
    state_dir = File.join(Dir.pwd, ".claude-task-master")
    FileUtils.rm_rf(state_dir) if File.directory?(state_dir)
  end
end
