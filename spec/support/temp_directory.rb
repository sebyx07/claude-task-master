# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Shared context for creating temporary directories in tests
RSpec.shared_context "with temp directory", :temp_dir do
  let(:temp_dir) { Dir.mktmpdir("claude-task-master-test") }

  around do |example|
    Dir.chdir(temp_dir) do
      example.run
    end
  ensure
    FileUtils.rm_rf(temp_dir) if File.directory?(temp_dir)
  end

  # Helper to create a .claude-task-master directory structure
  def setup_state_directory(files = {})
    state_dir = File.join(temp_dir, ".claude-task-master")
    FileUtils.mkdir_p(state_dir)
    FileUtils.mkdir_p(File.join(state_dir, "logs"))

    files.each do |filename, content|
      File.write(File.join(state_dir, filename), content)
    end

    state_dir
  end
end
