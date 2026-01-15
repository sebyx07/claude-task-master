# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeTaskMaster::Loop, :temp_dir do
  include_context "with loop helpers"

  let(:state) { ClaudeTaskMaster::State.new(temp_dir) }
  let(:loop) { described_class.new(state: state, model: "sonnet") }
  let(:goal) { "Build a REST API with authentication" }
  let(:criteria) { "All tests pass with 80%+ coverage" }

  describe "#initialize" do
    it "sets state" do
      expect(loop.state).to eq(state)
    end

    it "creates Claude instance with specified model" do
      expect(loop.claude).to be_a(ClaudeTaskMaster::Claude)
      expect(loop.claude.model).to eq("sonnet")
    end

    it "creates Pastel instance" do
      expect(loop.pastel).to respond_to(:cyan)
      expect(loop.pastel).to respond_to(:green)
      expect(loop.pastel).to respond_to(:red)
    end

    it "sets default options" do
      expect(loop.options).to eq({
        no_merge: false,
        max_sessions: nil,
        pause_on_pr: false,
        verbose: false
      })
    end

    it "accepts custom model parameter" do
      custom_loop = described_class.new(state: state, model: "opus")

      expect(custom_loop.claude.model).to eq("opus")
    end

    it "accepts no_merge option" do
      custom_loop = described_class.new(state: state, no_merge: true)

      expect(custom_loop.options[:no_merge]).to be true
    end

    it "accepts max_sessions option" do
      custom_loop = described_class.new(state: state, max_sessions: 10)

      expect(custom_loop.options[:max_sessions]).to eq(10)
    end

    it "accepts pause_on_pr option" do
      custom_loop = described_class.new(state: state, pause_on_pr: true)

      expect(custom_loop.options[:pause_on_pr]).to be true
    end

    it "accepts verbose option" do
      custom_loop = described_class.new(state: state, verbose: true)

      expect(custom_loop.options[:verbose]).to be true
    end

    it "accepts multiple options together" do
      custom_loop = described_class.new(
        state: state,
        model: "haiku",
        no_merge: true,
        max_sessions: 5,
        pause_on_pr: true,
        verbose: true
      )

      expect(custom_loop.claude.model).to eq("haiku")
      expect(custom_loop.options[:no_merge]).to be true
      expect(custom_loop.options[:max_sessions]).to eq(5)
      expect(custom_loop.options[:pause_on_pr]).to be true
      expect(custom_loop.options[:verbose]).to be true
    end
  end

  describe "#run" do
    before do
      stub_claude_invoke
      suppress_output
      # Stub both plan_phase and work_loop to prevent actual execution
      allow(loop).to receive(:plan_phase)
      allow(loop).to receive(:work_loop)
    end

    it "initializes state with goal and criteria" do
      loop.run(goal: goal, criteria: criteria)

      expect(state.goal).to eq(goal)
      expect(state.criteria).to eq(criteria)
    end

    it "calls plan_phase" do
      expect(loop).to receive(:plan_phase)

      loop.run(goal: goal, criteria: criteria)
    end

    it "calls work_loop" do
      expect(loop).to receive(:work_loop)

      loop.run(goal: goal, criteria: criteria)
    end
  end

  describe "#resume" do
    before do
      state.init(goal: goal, criteria: criteria)
      state.update_state(status: "ready", session_count: 3)
      stub_claude_invoke
      suppress_output
      # Stub work_loop to prevent infinite loop
      allow(loop).to receive(:work_loop)
    end

    it "raises error when no state exists" do
      empty_temp_dir = Dir.mktmpdir("claude-task-master-test-empty")
      state_no_existing = ClaudeTaskMaster::State.new(empty_temp_dir)
      loop_no_state = described_class.new(state: state_no_existing)

      begin
        expect {
          loop_no_state.resume
        }.to raise_error(ClaudeTaskMaster::ConfigError, /No existing state found/)
      ensure
        FileUtils.rm_rf(empty_temp_dir) if File.directory?(empty_temp_dir)
      end
    end

    it "resumes work_loop when status is ready" do
      expect(loop).not_to receive(:plan_phase)
      expect(loop).to receive(:work_loop)

      loop.resume
    end

    it "calls plan_phase when status is planning" do
      state.update_state(status: "planning")
      allow(loop).to receive(:plan_phase)
      expect(loop).to receive(:plan_phase)
      expect(loop).to receive(:work_loop)

      loop.resume
    end
  end
end
