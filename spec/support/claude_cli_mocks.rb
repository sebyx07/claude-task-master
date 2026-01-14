# frozen_string_literal: true

# Shared context for mocking Claude CLI calls
RSpec.shared_context "with mocked claude cli", :claude_cli do
  # Helper to mock a successful Claude CLI invocation
  def stub_claude_success(output: "Task completed successfully", exit_status: 0)
    allow(Open3).to receive(:popen2e).and_yield(
      nil, # stdin
      mock_output_io(output),
      mock_wait_thread(exit_status)
    )
  end

  # Helper to mock a failed Claude CLI invocation
  def stub_claude_failure(error: "Claude CLI error", exit_status: 1)
    allow(Open3).to receive(:popen2e).and_yield(
      nil,
      mock_output_io(error),
      mock_wait_thread(exit_status)
    )
  end

  # Helper to mock a timeout
  def stub_claude_timeout
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
  end

  private

  def mock_output_io(content)
    io = StringIO.new(content)
    allow(io).to receive(:read).and_return(content)
    allow(io).to receive(:each_line).and_yield(*content.lines)
    io
  end

  def mock_wait_thread(exit_status)
    thread = instance_double(Process::Status)
    allow(thread).to receive(:value).and_return(
      instance_double(Process::Status, exitstatus: exit_status, success?: exit_status.zero?)
    )
    thread
  end
end
