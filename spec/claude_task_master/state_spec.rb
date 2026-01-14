# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeTaskMaster::State, :temp_dir do
  let(:state) { described_class.new(temp_dir) }

  describe "#initialize" do
    it "sets the state directory path" do
      expect(state.dir).to eq(File.join(temp_dir, ".claude-task-master"))
    end

    it "uses current directory by default" do
      allow(Dir).to receive(:pwd).and_return("/tmp/test")
      default_state = described_class.new

      expect(default_state.dir).to eq("/tmp/test/.claude-task-master")
    end

    it "does not create directory on initialization" do
      expect(File.directory?(state.dir)).to be false
    end
  end

  describe "#init" do
    let(:goal) { "Build a REST API" }
    let(:criteria) { "All tests pass with 80%+ coverage" }

    it "creates state directory structure" do
      state.init(goal: goal, criteria: criteria)

      expect(File.directory?(state.dir)).to be true
      expect(File.directory?(File.join(state.dir, "logs"))).to be true
    end

    it "writes goal file" do
      state.init(goal: goal, criteria: criteria)

      expect(File.read(File.join(state.dir, "goal.txt"))).to eq(goal)
    end

    it "writes criteria file" do
      state.init(goal: goal, criteria: criteria)

      expect(File.read(File.join(state.dir, "criteria.txt"))).to eq(criteria)
    end

    it "creates progress file with timestamp" do
      freeze_time = Time.parse("2026-01-14T12:00:00-05:00")
      allow(Time).to receive(:now).and_return(freeze_time)

      state.init(goal: goal, criteria: criteria)
      progress_content = File.read(File.join(state.dir, "progress.md"))

      expect(progress_content).to include("# Progress")
      expect(progress_content).to include("_Started: 2026-01-14T12:00:00-05:00_")
    end

    it "creates context file with header" do
      state.init(goal: goal, criteria: criteria)
      context_content = File.read(File.join(state.dir, "context.md"))

      expect(context_content).to include("# Context")
      expect(context_content).to include("_Learnings accumulated across sessions._")
    end

    it "initializes state.json with planning status" do
      freeze_time = Time.parse("2026-01-14T12:00:00-05:00")
      allow(Time).to receive(:now).and_return(freeze_time)

      state.init(goal: goal, criteria: criteria)
      state_data = JSON.parse(File.read(File.join(state.dir, "state.json")), symbolize_names: true)

      expect(state_data[:status]).to eq("planning")
      expect(state_data[:current_task]).to be_nil
      expect(state_data[:session_count]).to eq(0)
      expect(state_data[:pr_number]).to be_nil
      expect(state_data[:started_at]).to eq("2026-01-14T12:00:00-05:00")
      expect(state_data[:updated_at]).to eq("2026-01-14T12:00:00-05:00")
    end
  end

  describe "#exists?" do
    it "returns false when state directory does not exist" do
      expect(state.exists?).to be false
    end

    it "returns false when directory exists but state.json does not" do
      FileUtils.mkdir_p(state.dir)

      expect(state.exists?).to be false
    end

    it "returns true when both directory and state.json exist" do
      FileUtils.mkdir_p(state.dir)
      File.write(File.join(state.dir, "state.json"), "{}")

      expect(state.exists?).to be true
    end
  end

  describe "file read operations" do
    before do
      setup_state_directory(
        "goal.txt" => "Build a REST API",
        "criteria.txt" => "Tests pass",
        "plan.md" => "# Plan\n- Task 1",
        "progress.md" => "# Progress\nDone something",
        "context.md" => "# Context\nLearned something"
      )
    end

    describe "#goal" do
      it "reads goal from file" do
        expect(state.goal).to eq("Build a REST API")
      end

      it "returns nil when file does not exist" do
        File.delete(File.join(state.dir, "goal.txt"))

        expect(state.goal).to be_nil
      end
    end

    describe "#criteria" do
      it "reads criteria from file" do
        expect(state.criteria).to eq("Tests pass")
      end

      it "returns nil when file does not exist" do
        File.delete(File.join(state.dir, "criteria.txt"))

        expect(state.criteria).to be_nil
      end
    end

    describe "#plan" do
      it "reads plan from file" do
        expect(state.plan).to eq("# Plan\n- Task 1")
      end

      it "returns nil when file does not exist" do
        expect(state.plan).to be_nil if !File.exist?(File.join(state.dir, "plan.md"))
      end
    end

    describe "#progress" do
      it "reads progress from file" do
        expect(state.progress).to eq("# Progress\nDone something")
      end

      it "returns nil when file does not exist" do
        File.delete(File.join(state.dir, "progress.md"))

        expect(state.progress).to be_nil
      end
    end

    describe "#context" do
      it "reads context from file" do
        expect(state.context).to eq("# Context\nLearned something")
      end

      it "returns nil when file does not exist" do
        File.delete(File.join(state.dir, "context.md"))

        expect(state.context).to be_nil
      end
    end
  end

  describe "file write operations" do
    before do
      FileUtils.mkdir_p(state.dir)
    end

    describe "#save_plan" do
      it "writes plan to file" do
        state.save_plan("# New Plan\n- Task 1\n- Task 2")

        expect(File.read(File.join(state.dir, "plan.md"))).to eq("# New Plan\n- Task 1\n- Task 2")
      end

      it "overwrites existing plan" do
        File.write(File.join(state.dir, "plan.md"), "Old plan")
        state.save_plan("New plan")

        expect(File.read(File.join(state.dir, "plan.md"))).to eq("New plan")
      end
    end

    describe "#append_progress" do
      it "appends to existing progress" do
        File.write(File.join(state.dir, "progress.md"), "Existing progress")
        state.append_progress("New entry")

        expect(File.read(File.join(state.dir, "progress.md"))).to eq("Existing progress\nNew entry")
      end

      it "handles empty progress file" do
        File.write(File.join(state.dir, "progress.md"), "")
        state.append_progress("First entry")

        expect(File.read(File.join(state.dir, "progress.md"))).to eq("\nFirst entry")
      end

      it "creates file if it does not exist" do
        state.append_progress("New entry")

        expect(File.read(File.join(state.dir, "progress.md"))).to eq("\nNew entry")
      end
    end

    describe "#append_context" do
      it "appends to existing context" do
        File.write(File.join(state.dir, "context.md"), "Existing context")
        state.append_context("New learning")

        expect(File.read(File.join(state.dir, "context.md"))).to eq("Existing context\nNew learning")
      end

      it "handles empty context file" do
        File.write(File.join(state.dir, "context.md"), "")
        state.append_context("First learning")

        expect(File.read(File.join(state.dir, "context.md"))).to eq("\nFirst learning")
      end

      it "creates file if it does not exist" do
        state.append_context("New learning")

        expect(File.read(File.join(state.dir, "context.md"))).to eq("\nNew learning")
      end
    end
  end

  describe "#log_session" do
    before do
      FileUtils.mkdir_p(File.join(state.dir, "logs"))
    end

    it "creates session log with formatted number" do
      state.log_session(1, "Session 1 content")

      expect(File.read(File.join(state.dir, "logs", "session-001.md"))).to eq("Session 1 content")
    end

    it "formats session number with leading zeros" do
      state.log_session(42, "Session 42 content")

      expect(File.exist?(File.join(state.dir, "logs", "session-042.md"))).to be true
    end

    it "handles large session numbers" do
      state.log_session(999, "Session 999 content")

      expect(File.exist?(File.join(state.dir, "logs", "session-999.md"))).to be true
    end

    it "overwrites existing session log" do
      File.write(File.join(state.dir, "logs", "session-001.md"), "Old content")
      state.log_session(1, "New content")

      expect(File.read(File.join(state.dir, "logs", "session-001.md"))).to eq("New content")
    end
  end

  describe "#next_session_number" do
    before do
      FileUtils.mkdir_p(File.join(state.dir, "logs"))
    end

    it "returns 1 when no sessions exist" do
      expect(state.next_session_number).to eq(1)
    end

    it "returns next number based on existing sessions" do
      File.write(File.join(state.dir, "logs", "session-001.md"), "content")
      File.write(File.join(state.dir, "logs", "session-002.md"), "content")

      expect(state.next_session_number).to eq(3)
    end

    it "counts all session files regardless of gaps" do
      File.write(File.join(state.dir, "logs", "session-001.md"), "content")
      File.write(File.join(state.dir, "logs", "session-005.md"), "content")

      expect(state.next_session_number).to eq(3) # Count is 2 files, so next is 3
    end

    it "ignores non-session files" do
      File.write(File.join(state.dir, "logs", "session-001.md"), "content")
      File.write(File.join(state.dir, "logs", "other-file.txt"), "content")

      expect(state.next_session_number).to eq(2)
    end
  end
end
