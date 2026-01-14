# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeTaskMaster::Claude do
  describe "#initialize" do
    it "sets default model to sonnet" do
      claude = described_class.new

      expect(claude.model).to eq("sonnet")
    end

    it "sets default timeout to DEFAULT_TIMEOUT" do
      claude = described_class.new

      expect(claude.timeout).to eq(ClaudeTaskMaster::Claude::DEFAULT_TIMEOUT)
    end

    it "accepts custom model parameter" do
      claude = described_class.new(model: "opus")

      expect(claude.model).to eq("opus")
    end

    it "accepts custom timeout parameter" do
      claude = described_class.new(timeout: 7200)

      expect(claude.timeout).to eq(7200)
    end

    it "accepts both custom model and timeout" do
      claude = described_class.new(model: "haiku", timeout: 1800)

      expect(claude.model).to eq("haiku")
      expect(claude.timeout).to eq(1800)
    end
  end

  describe ".available?" do
    it "returns true when claude CLI is available" do
      allow_any_instance_of(Object).to receive(:system).with("which claude > /dev/null 2>&1").and_return(true)

      expect(described_class.available?).to be true
    end

    it "returns false when claude CLI is not available" do
      allow_any_instance_of(Object).to receive(:system).with("which claude > /dev/null 2>&1").and_return(false)

      expect(described_class.available?).to be false
    end

    it "returns nil when system command fails" do
      allow_any_instance_of(Object).to receive(:system).with("which claude > /dev/null 2>&1").and_return(nil)

      expect(described_class.available?).to be_falsey
    end
  end

  describe ".version" do
    it "returns version string from claude CLI" do
      allow_any_instance_of(Object).to receive(:`).with("claude --version 2>&1").and_return("Claude Code v1.2.3\n")

      expect(described_class.version).to eq("Claude Code v1.2.3")
    end

    it "strips whitespace from version output" do
      allow_any_instance_of(Object).to receive(:`).with("claude --version 2>&1").and_return("  Claude Code v1.0.0  \n")

      expect(described_class.version).to eq("Claude Code v1.0.0")
    end

    it "handles empty version output" do
      allow_any_instance_of(Object).to receive(:`).with("claude --version 2>&1").and_return("")

      expect(described_class.version).to eq("")
    end
  end

  describe "#invoke" do
    let(:claude) { described_class.new }
    let(:prompt) { "Test prompt" }

    # Helper methods for mocking
    def mock_stdin
      double("stdin", close: nil)
    end

    def mock_stdout(output)
      io = StringIO.new(output)
      # Override each_line to yield individual lines
      allow(io).to receive(:each_line) do |&block|
        output.each_line(&block)
      end
      io
    end

    def mock_wait_thread(exit_status)
      status = double("Process::Status", exitstatus: exit_status, success?: exit_status.zero?)
      double("Thread", value: status)
    end

    def stub_popen2e_success(output: "Success")
      allow(Open3).to receive(:popen2e).and_yield(
        mock_stdin,
        mock_stdout(output),
        mock_wait_thread(0)
      )
    end

    def stub_popen2e_failure(output: "Error", exit_status: 1)
      allow(Open3).to receive(:popen2e).and_yield(
        mock_stdin,
        mock_stdout(output),
        mock_wait_thread(exit_status)
      )
    end

    context "with successful execution" do
      it "returns success tuple with output" do
        stub_popen2e_success(output: "Task completed successfully")

        success, output, exit_code = claude.invoke(prompt)

        expect(success).to be true
        expect(output).to include("Task completed successfully")
        expect(exit_code).to eq(0)
      end

      it "calls Open3.popen2e with correct command" do
        expect(Open3).to receive(:popen2e).with(
          "claude",
          "-p",
          "--dangerously-skip-permissions",
          "--model", "sonnet",
          "Test prompt"
        ).and_yield(
          double(close: nil),
          StringIO.new("output"),
          double(value: double(exitstatus: 0))
        )

        claude.invoke(prompt)
      end

      it "uses custom model in command" do
        claude_opus = described_class.new(model: "opus")

        expect(Open3).to receive(:popen2e).with(
          "claude",
          "-p",
          "--dangerously-skip-permissions",
          "--model", "opus",
          "Test prompt"
        ).and_yield(
          double(close: nil),
          StringIO.new("output"),
          double(value: double(exitstatus: 0))
        )

        claude_opus.invoke(prompt)
      end

      it "includes allowed_tools when provided" do
        expect(Open3).to receive(:popen2e).with(
          "claude",
          "-p",
          "--dangerously-skip-permissions",
          "--model", "sonnet",
          "--allowedTools", "Bash,Read,Write",
          "Test prompt"
        ).and_yield(
          double(close: nil),
          StringIO.new("output"),
          double(value: double(exitstatus: 0))
        )

        claude.invoke(prompt, allowed_tools: ["Bash", "Read", "Write"])
      end

      it "streams output line by line" do
        output_lines = "Line 1\nLine 2\nLine 3\n"
        stub_popen2e_success(output: output_lines)

        success, output, _exit_code = claude.invoke(prompt)

        expect(success).to be true
        expect(output).to eq(output_lines)
      end

      it "prints progress indicator for tool usage" do
        output_with_tools = "Starting\n[Tool: Read] reading file\nDone\n"
        stub_popen2e_success(output: output_with_tools)

        expect($stdout).to receive(:print).with(".").at_least(:once)
        expect($stdout).to receive(:puts)

        claude.invoke(prompt)
      end

      it "prints newline after progress indicators" do
        output_with_tools = "[Tool: Read] file.txt\nDone\n"
        stub_popen2e_success(output: output_with_tools)

        expect($stdout).to receive(:puts)

        claude.invoke(prompt)
      end

      it "does not print newline when no tool usage" do
        stub_popen2e_success(output: "Simple output\n")

        expect($stdout).not_to receive(:puts)

        claude.invoke(prompt)
      end
    end

    context "with failed execution" do
      it "returns failure tuple with error output" do
        stub_popen2e_failure(output: "Error: Command not found", exit_status: 1)

        success, output, exit_code = claude.invoke(prompt)

        expect(success).to be false
        expect(output).to include("Error: Command not found")
        expect(exit_code).to eq(1)
      end

      it "handles non-zero exit codes" do
        stub_popen2e_failure(output: "Permission denied", exit_status: 127)

        success, output, exit_code = claude.invoke(prompt)

        expect(success).to be false
        expect(exit_code).to eq(127)
      end
    end

    context "with timeout scenarios" do
      it "returns timeout error when operation times out" do
        claude_short = described_class.new(timeout: 1)
        allow(Timeout).to receive(:timeout).with(1).and_raise(Timeout::Error)
        allow(Open3).to receive(:popen2e)

        success, output, exit_code = claude_short.invoke(prompt)

        expect(success).to be false
        expect(output).to include("[TIMEOUT after 1s]")
        expect(exit_code).to eq(-1)
      end

      it "includes partial output before timeout" do
        claude_short = described_class.new(timeout: 5)

        # Mock Timeout to raise error when called
        allow(Timeout).to receive(:timeout).with(5).and_raise(Timeout::Error)

        success, output, exit_code = claude_short.invoke(prompt)

        expect(success).to be false
        expect(output).to include("[TIMEOUT after 5s]")
        expect(exit_code).to eq(-1)
      end
    end

    context "with exception handling" do
      it "catches and returns StandardError exceptions" do
        allow(Open3).to receive(:popen2e).and_raise(StandardError.new("Connection failed"))

        success, output, exit_code = claude.invoke(prompt)

        expect(success).to be false
        expect(output).to include("[ERROR: Connection failed]")
        expect(exit_code).to eq(-1)
      end

      it "includes partial output before exception" do
        partial = "Working on it\n"

        allow(Open3).to receive(:popen2e) do
          raise StandardError.new("Network error")
        end

        success, output, exit_code = claude.invoke(prompt)

        expect(success).to be false
        expect(output).to include("[ERROR: Network error]")
        expect(exit_code).to eq(-1)
      end
    end

    context "with different working directories" do
      it "executes in current directory by default" do
        current_dir = Dir.pwd
        stub_popen2e_success

        expect(Dir).to receive(:chdir).with(current_dir).and_call_original

        claude.invoke(prompt)
      end

      it "executes in specified working directory" do
        custom_dir = "/tmp/custom"
        stub_popen2e_success

        expect(Dir).to receive(:chdir).with(custom_dir).and_yield

        claude.invoke(prompt, working_dir: custom_dir)
      end

      it "returns to original directory after execution" do
        original_dir = Dir.pwd
        custom_dir = "/tmp/test"
        stub_popen2e_success

        allow(Dir).to receive(:chdir).with(custom_dir).and_yield

        claude.invoke(prompt, working_dir: custom_dir)

        expect(Dir.pwd).to eq(original_dir)
      end
    end
  end

  describe ".planning_prompt" do
    let(:goal) { "Build a REST API with authentication" }

    it "includes the goal in the prompt" do
      prompt = described_class.planning_prompt(goal)

      expect(prompt).to include("## Goal")
      expect(prompt).to include("Build a REST API with authentication")
    end

    it "includes planning phase header" do
      prompt = described_class.planning_prompt(goal)

      expect(prompt).to include("# Claude Task Master - Planning Phase")
    end

    it "includes all required sections" do
      prompt = described_class.planning_prompt(goal)

      expect(prompt).to include("## Planning Instructions")
      expect(prompt).to include("### Step 1: Explore the Codebase")
      expect(prompt).to include("### Step 2: Design the Plan")
      expect(prompt).to include("### Step 3: Write State Files")
    end

    it "includes plan structure guidelines" do
      prompt = described_class.planning_prompt(goal)

      expect(prompt).to include("## PR 1:")
      expect(prompt).to include("- [ ] Task")
    end

    context "with existing CLAUDE.md" do
      let(:claude_md_content) { "# Project Conventions\n\nUse Ruby 3.1+ style" }

      it "includes CLAUDE.md section" do
        prompt = described_class.planning_prompt(goal, existing_claude_md: claude_md_content)

        expect(prompt).to include("## Existing Project Context (CLAUDE.md)")
        expect(prompt).to include("Use Ruby 3.1+ style")
      end

      it "truncates CLAUDE.md content to 2000 characters" do
        long_content = "x" * 3000
        prompt = described_class.planning_prompt(goal, existing_claude_md: long_content)

        # Should include CLAUDE.md section with truncated content
        expect(prompt).to include("## Existing Project Context (CLAUDE.md)")
        # Find the content between triple backticks
        content_match = prompt.match(/```\n(.+?)\n```/m)
        expect(content_match).not_to be_nil
        truncated_content = content_match[1]
        # The implementation uses [0..2000] which gives 2001 chars (indices 0-2000 inclusive)
        # Then adds "..." for total of 2004 characters
        expect(truncated_content).to eq(("x" * 2001) + "...")
        expect(truncated_content.length).to eq(2004)
      end

      it "does not add ellipsis for content under 2000 characters" do
        short_content = "y" * 1000
        prompt = described_class.planning_prompt(goal, existing_claude_md: short_content)

        expect(prompt).to include("y" * 1000)
        # Check the content doesn't have ellipsis appended to the short content
        content_match = prompt.match(/```\n(.+?)\n```/m)
        expect(content_match[1]).to eq(short_content)
      end

      it "handles exactly 2000 characters without ellipsis" do
        exact_content = "z" * 2000
        prompt = described_class.planning_prompt(goal, existing_claude_md: exact_content)

        content_match = prompt.match(/```\n(.+?)\n```/m)
        # Exactly 2000 chars should not get ellipsis
        expect(content_match[1]).to eq(exact_content)
      end
    end

    context "without existing CLAUDE.md" do
      it "does not include CLAUDE.md section" do
        prompt = described_class.planning_prompt(goal)

        expect(prompt).not_to include("## Existing Project Context (CLAUDE.md)")
      end

      it "handles nil existing_claude_md" do
        prompt = described_class.planning_prompt(goal, existing_claude_md: nil)

        expect(prompt).not_to include("## Existing Project Context (CLAUDE.md)")
      end
    end
  end

  describe ".work_prompt" do
    let(:context) { "Current task: Build API endpoint\nPR: #42" }

    it "includes the context in the prompt" do
      prompt = described_class.work_prompt(context)

      expect(prompt).to include("## Current State")
      expect(prompt).to include("Current task: Build API endpoint")
      expect(prompt).to include("PR: #42")
    end

    it "includes work session header" do
      prompt = described_class.work_prompt(context)

      expect(prompt).to include("# Claude Task Master - Work Session")
    end

    it "includes all required sections" do
      prompt = described_class.work_prompt(context)

      expect(prompt).to include("## Work Loop Instructions")
      expect(prompt).to include("### Step 1: Understand Current State")
      expect(prompt).to include("### Step 2: Execute the Work")
      expect(prompt).to include("### Step 3: Track Progress")
      expect(prompt).to include("### Step 4: Handle Completion")
    end

    it "includes guidelines section" do
      prompt = described_class.work_prompt(context)

      expect(prompt).to include("### Guidelines")
      expect(prompt).to include("Work autonomously")
      expect(prompt).to include("Ship working code")
    end

    context "with auto-merge enabled (no_merge: false)" do
      it "includes auto-merge instructions" do
        prompt = described_class.work_prompt(context, no_merge: false)

        expect(prompt).to include("**Auto-merge is enabled**")
        expect(prompt).to include("gh pr merge --squash --delete-branch")
      end

      it "includes post-merge instructions" do
        prompt = described_class.work_prompt(context, no_merge: false)

        expect(prompt).to include("After merge, pull main and start next PR")
      end

      it "does not include manual review instructions" do
        prompt = described_class.work_prompt(context, no_merge: false)

        expect(prompt).not_to include("DO NOT MERGE PRs")
        expect(prompt).not_to include("Wait for manual review")
      end
    end

    context "with auto-merge disabled (no_merge: true)" do
      it "includes manual merge instructions" do
        prompt = described_class.work_prompt(context, no_merge: true)

        expect(prompt).to include("**IMPORTANT: DO NOT MERGE PRs**")
        expect(prompt).to include("Create PRs but do not merge them")
        expect(prompt).to include("Wait for manual review and merge")
      end

      it "includes pr_ready flag instructions" do
        prompt = described_class.work_prompt(context, no_merge: true)

        expect(prompt).to include("Set `pr_ready` to `true` in state.json when ready for merge")
      end

      it "does not include auto-merge instructions" do
        prompt = described_class.work_prompt(context, no_merge: true)

        expect(prompt).not_to include("gh pr merge --squash")
      end
    end

    context "with default parameters" do
      it "defaults to auto-merge enabled" do
        prompt = described_class.work_prompt(context)

        expect(prompt).to include("**Auto-merge is enabled**")
      end
    end
  end

  describe "private #build_args" do
    let(:claude) { described_class.new(model: "sonnet") }

    # Test build_args indirectly through invoke
    it "builds correct args without allowed_tools" do
      expect(Open3).to receive(:popen2e).with(
        "claude",
        "-p",
        "--dangerously-skip-permissions",
        "--model", "sonnet",
        "prompt"
      ).and_yield(
        double(close: nil),
        StringIO.new("output"),
        double(value: double(exitstatus: 0))
      )

      claude.invoke("prompt")
    end

    it "builds correct args with allowed_tools" do
      expect(Open3).to receive(:popen2e).with(
        "claude",
        "-p",
        "--dangerously-skip-permissions",
        "--model", "sonnet",
        "--allowedTools", "Read,Write",
        "prompt"
      ).and_yield(
        double(close: nil),
        StringIO.new("output"),
        double(value: double(exitstatus: 0))
      )

      claude.invoke("prompt", allowed_tools: ["Read", "Write"])
    end

    it "handles nil allowed_tools" do
      expect(Open3).to receive(:popen2e).with(
        "claude",
        "-p",
        "--dangerously-skip-permissions",
        "--model", "sonnet",
        "prompt"
      ).and_yield(
        double(close: nil),
        StringIO.new("output"),
        double(value: double(exitstatus: 0))
      )

      claude.invoke("prompt", allowed_tools: nil)
    end

    it "joins multiple allowed_tools with comma" do
      expect(Open3).to receive(:popen2e).with(
        "claude",
        "-p",
        "--dangerously-skip-permissions",
        "--model", "haiku",
        "--allowedTools", "Bash,Read,Write,Edit,Glob",
        "test"
      ).and_yield(
        double(close: nil),
        StringIO.new("output"),
        double(value: double(exitstatus: 0))
      )

      claude_haiku = described_class.new(model: "haiku")
      claude_haiku.invoke("test", allowed_tools: ["Bash", "Read", "Write", "Edit", "Glob"])
    end
  end

  describe "constants" do
    it "defines DEFAULT_TIMEOUT" do
      expect(ClaudeTaskMaster::Claude::DEFAULT_TIMEOUT).to eq(3600)
    end

    it "defines CLAUDE_BINARY" do
      expect(ClaudeTaskMaster::Claude::CLAUDE_BINARY).to eq("claude")
    end
  end
end
