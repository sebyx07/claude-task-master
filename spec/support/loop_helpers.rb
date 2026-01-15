# frozen_string_literal: true

# Shared helpers for Loop testing
RSpec.shared_context "with loop helpers" do
  # Helper to load a fixture file
  def load_fixture(filename)
    File.read(File.join(__dir__, "..", "fixtures", filename))
  end

  # Helper to stub Claude CLI invocation with fixture
  def stub_claude_with_fixture(fixture_name, exit_status: 0)
    output = load_fixture("claude_output/#{fixture_name}")
    stub_claude_invoke(output: output, exit_status: exit_status)
  end

  # Helper to stub Claude invoke method directly
  def stub_claude_invoke(output: "Success", exit_status: 0)
    stdin = double("stdin", close: nil)
    stdout = StringIO.new(output)
    allow(stdout).to receive(:each_line) { |&block| output.each_line(&block) }
    wait_thread = double("Thread", value: double("Process::Status", exitstatus: exit_status, success?: exit_status.zero?))

    allow(Open3).to receive(:popen2e).and_yield(stdin, stdout, wait_thread)
  end

  # Helper to stub GitHub PR status
  def stub_github_pr_status(status: :passing, unresolved: [])
    allow(ClaudeTaskMaster::GitHub).to receive(:pr_status).and_return({ status: status })
    allow(ClaudeTaskMaster::GitHub).to receive(:unresolved_threads).and_return(unresolved)
  end

  # Helper to stub GitHub API error
  def stub_github_api_error(error_class: StandardError, message: "API error")
    allow(ClaudeTaskMaster::GitHub).to receive(:pr_status).and_raise(error_class.new(message))
    allow(ClaudeTaskMaster::GitHub).to receive(:unresolved_threads).and_raise(error_class.new(message))
  end

  # Helper to suppress output during tests
  def suppress_output
    allow($stdout).to receive(:print)
    allow($stdout).to receive(:puts)
  end

  # Helper to capture actual output
  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # Helper to setup state with files
  def setup_loop_state_files(files = {})
    state_dir = File.join(temp_dir, ".claude-task-master")
    FileUtils.mkdir_p(state_dir)
    FileUtils.mkdir_p(File.join(state_dir, "logs"))

    default_files = {
      "goal.txt" => "Build a REST API",
      "criteria.txt" => "All tests pass",
      "plan.md" => "# Plan\n- [ ] Task 1\n- [ ] Task 2",
      "state.json" => JSON.generate({
        status: "working",
        current_task: "Task 1",
        session_count: 1,
        pr_number: nil
      })
    }

    default_files.merge(files).each do |filename, content|
      File.write(File.join(state_dir, filename), content)
    end

    state_dir
  end
end
