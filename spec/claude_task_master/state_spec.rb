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

  describe "state management" do
    before do
      FileUtils.mkdir_p(state.dir)
    end

    describe "#load_state" do
      it "returns nil when state file does not exist" do
        expect(state.load_state).to be_nil
      end

      it "loads state from JSON file with symbol keys" do
        state_data = {
          status: "working",
          current_task: "Build feature",
          session_count: 5
        }
        File.write(File.join(state.dir, "state.json"), JSON.generate(state_data))

        loaded = state.load_state

        expect(loaded[:status]).to eq("working")
        expect(loaded[:current_task]).to eq("Build feature")
        expect(loaded[:session_count]).to eq(5)
      end

      it "handles empty state file" do
        File.write(File.join(state.dir, "state.json"), "{}")

        expect(state.load_state).to eq({})
      end

      it "parses nested data structures" do
        state_data = {
          status: "blocked",
          pr_data: {
            number: 42,
            url: "https://github.com/user/repo/pull/42"
          }
        }
        File.write(File.join(state.dir, "state.json"), JSON.generate(state_data))

        loaded = state.load_state

        expect(loaded[:pr_data][:number]).to eq(42)
        expect(loaded[:pr_data][:url]).to eq("https://github.com/user/repo/pull/42")
      end
    end

    describe "#save_state" do
      it "saves state as JSON with pretty formatting" do
        state.save_state(status: "working", current_task: "Build API")

        content = File.read(File.join(state.dir, "state.json"))
        parsed = JSON.parse(content, symbolize_names: true)

        expect(parsed[:status]).to eq("working")
        expect(parsed[:current_task]).to eq("Build API")
      end

      it "automatically adds updated_at timestamp" do
        freeze_time = Time.parse("2026-01-14T15:30:00-05:00")
        allow(Time).to receive(:now).and_return(freeze_time)

        state.save_state(status: "planning")
        parsed = JSON.parse(File.read(File.join(state.dir, "state.json")), symbolize_names: true)

        expect(parsed[:updated_at]).to eq("2026-01-14T15:30:00-05:00")
      end

      it "overwrites existing state" do
        File.write(File.join(state.dir, "state.json"), JSON.generate(status: "old"))
        state.save_state(status: "new", task: "New task")

        parsed = JSON.parse(File.read(File.join(state.dir, "state.json")), symbolize_names: true)

        expect(parsed[:status]).to eq("new")
        expect(parsed[:task]).to eq("New task")
      end

      it "preserves complex data types" do
        state.save_state(
          status: "working",
          counts: [1, 2, 3],
          metadata: { key: "value" },
          flag: true
        )

        parsed = JSON.parse(File.read(File.join(state.dir, "state.json")), symbolize_names: true)

        expect(parsed[:counts]).to eq([1, 2, 3])
        expect(parsed[:metadata][:key]).to eq("value")
        expect(parsed[:flag]).to be true
      end
    end

    describe "#update_state" do
      it "merges new fields with existing state" do
        state.save_state(status: "working", session_count: 1)
        state.update_state(current_task: "New task")

        loaded = state.load_state

        expect(loaded[:status]).to eq("working")
        expect(loaded[:session_count]).to eq(1)
        expect(loaded[:current_task]).to eq("New task")
      end

      it "overwrites existing fields" do
        state.save_state(status: "working", current_task: "Old task")
        state.update_state(status: "blocked", current_task: "New task")

        loaded = state.load_state

        expect(loaded[:status]).to eq("blocked")
        expect(loaded[:current_task]).to eq("New task")
      end

      it "handles empty existing state" do
        state.update_state(status: "planning", session_count: 0)

        loaded = state.load_state

        expect(loaded[:status]).to eq("planning")
        expect(loaded[:session_count]).to eq(0)
      end

      it "updates timestamp on each update" do
        freeze_time1 = Time.parse("2026-01-14T10:00:00-05:00")
        freeze_time2 = Time.parse("2026-01-14T11:00:00-05:00")

        allow(Time).to receive(:now).and_return(freeze_time1)
        state.save_state(status: "working")

        allow(Time).to receive(:now).and_return(freeze_time2)
        state.update_state(current_task: "Task")

        loaded = state.load_state
        expect(loaded[:updated_at]).to eq("2026-01-14T11:00:00-05:00")
      end
    end
  end

  describe "#build_context" do
    before do
      FileUtils.mkdir_p(state.dir)
    end

    it "builds complete context string with all sections" do
      File.write(File.join(state.dir, "goal.txt"), "Build a REST API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      File.write(File.join(state.dir, "plan.md"), "# Plan\n- Task 1\n- Task 2")
      File.write(File.join(state.dir, "context.md"), "# Context\nLearned X")
      File.write(File.join(state.dir, "progress.md"), "# Progress\nDone Y")
      state.save_state(
        status: "working",
        current_task: "Task 1",
        pr_number: 42,
        session_count: 5
      )

      context = state.build_context

      expect(context).to include("# Current State")
      expect(context).to include("## Goal")
      expect(context).to include("Build a REST API")
      expect(context).to include("## Success Criteria")
      expect(context).to include("Tests pass")
      expect(context).to include("## Status")
      expect(context).to include("Phase: working")
      expect(context).to include("Current task: Task 1")
      expect(context).to include("PR: #42")
      expect(context).to include("Session: 5")
      expect(context).to include("## Plan")
      expect(context).to include("- Task 1")
      expect(context).to include("## Context from Previous Sessions")
      expect(context).to include("Learned X")
      expect(context).to include("## Recent Progress")
      expect(context).to include("Done Y")
    end

    it "handles missing goal file" do
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "working")

      context = state.build_context

      expect(context).to include("## Goal")
      expect(context).not_to include("Build")
    end

    it "handles missing criteria file" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      state.save_state(status: "working")

      context = state.build_context

      expect(context).to include("## Success Criteria")
      expect(context).not_to include("Tests")
    end

    it "shows placeholder when no plan exists" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "planning")

      context = state.build_context

      expect(context).to include("_No plan yet. Generate one first._")
    end

    it "shows placeholder when no context exists" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "working")

      context = state.build_context

      expect(context).to include("_No context yet._")
    end

    it "shows placeholder when no progress exists" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "working")

      context = state.build_context

      expect(context).to include("_No progress yet._")
    end

    it "handles missing state file" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")

      context = state.build_context

      expect(context).to include("Phase: unknown")
      expect(context).to include("Current task: none")
      expect(context).to include("PR: none")
      expect(context).to include("Session: 0")
    end

    it "shows 'none' when no PR number" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "working", pr_number: nil)

      context = state.build_context

      expect(context).to include("PR: none")
    end

    it "formats PR number with hash" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "working", pr_number: 123)

      context = state.build_context

      expect(context).to include("PR: #123")
    end

    it "handles nil current_task" do
      File.write(File.join(state.dir, "goal.txt"), "Build API")
      File.write(File.join(state.dir, "criteria.txt"), "Tests pass")
      state.save_state(status: "planning", current_task: nil)

      context = state.build_context

      expect(context).to include("Current task: none")
    end
  end

  describe "status checks" do
    before do
      FileUtils.mkdir_p(state.dir)
    end

    describe "#success?" do
      it "returns true when status is success" do
        state.save_state(status: "success")

        expect(state.success?).to be true
      end

      it "returns false when status is not success" do
        state.save_state(status: "working")

        expect(state.success?).to be false
      end

      it "returns false when state file does not exist" do
        expect(state.success?).to be_falsey
      end

      it "returns false when status is nil" do
        state.save_state(current_task: "task")

        expect(state.success?).to be false
      end
    end

    describe "#blocked?" do
      it "returns true when status is blocked" do
        state.save_state(status: "blocked")

        expect(state.blocked?).to be true
      end

      it "returns false when status is not blocked" do
        state.save_state(status: "working")

        expect(state.blocked?).to be false
      end

      it "returns false when state file does not exist" do
        expect(state.blocked?).to be_falsey
      end
    end

    describe "#blocked_reason" do
      it "returns notes field when available" do
        state.save_state(status: "blocked", notes: "CI failing")

        expect(state.blocked_reason).to eq("CI failing")
      end

      it "returns blocked_reason field when notes not available" do
        state.save_state(status: "blocked", blocked_reason: "Tests failing")

        expect(state.blocked_reason).to eq("Tests failing")
      end

      it "prefers notes over blocked_reason" do
        state.save_state(status: "blocked", notes: "Primary reason", blocked_reason: "Fallback")

        expect(state.blocked_reason).to eq("Primary reason")
      end

      it "returns default message when no reason provided" do
        state.save_state(status: "blocked")

        expect(state.blocked_reason).to eq("No reason provided")
      end

      it "returns nil when state does not exist" do
        expect(state.blocked_reason).to be_nil
      end
    end
  end
end
