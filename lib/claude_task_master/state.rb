# frozen_string_literal: true

require 'json'
require 'fileutils'

module ClaudeTaskMaster
  # Manages state persistence in .claude-task-master/
  # All state is file-based for easy inspection and resumption
  class State
    GOAL_FILE = 'goal.txt'
    CRITERIA_FILE = 'criteria.txt'
    PLAN_FILE = 'plan.md'
    STATE_FILE = 'state.json'
    PROGRESS_FILE = 'progress.md'
    CONTEXT_FILE = 'context.md'
    LOGS_DIR = 'logs'

    attr_reader :dir

    def initialize(project_dir = Dir.pwd)
      @dir = File.join(project_dir, STATE_DIR)
    end

    # Initialize state directory for new project
    def init(goal:, criteria:)
      FileUtils.mkdir_p(@dir)
      FileUtils.mkdir_p(logs_dir)

      write_file(GOAL_FILE, goal)
      write_file(CRITERIA_FILE, criteria)
      write_file(PROGRESS_FILE, "# Progress\n\n_Started: #{Time.now.iso8601}_\n\n")
      write_file(CONTEXT_FILE, "# Context\n\n_Learnings accumulated across sessions._\n\n")

      save_state(
        status: 'planning',
        current_task: nil,
        session_count: 0,
        pr_number: nil,
        started_at: Time.now.iso8601,
        updated_at: Time.now.iso8601
      )
    end

    # Check if state directory exists (for resume)
    def exists?
      File.directory?(@dir) && File.exist?(state_path)
    end

    # Load machine state
    def load_state
      return nil unless File.exist?(state_path)

      JSON.parse(File.read(state_path), symbolize_names: true)
    end

    # Save machine state
    def save_state(data)
      data[:updated_at] = Time.now.iso8601
      File.write(state_path, JSON.pretty_generate(data))
    end

    # Update specific state fields
    def update_state(**fields)
      current = load_state || {}
      save_state(current.merge(fields))
    end

    # Read goal
    def goal
      read_file(GOAL_FILE)
    end

    # Read success criteria
    def criteria
      read_file(CRITERIA_FILE)
    end

    # Read plan
    def plan
      read_file(PLAN_FILE)
    end

    # Write plan
    def save_plan(content)
      write_file(PLAN_FILE, content)
    end

    # Read progress notes
    def progress
      read_file(PROGRESS_FILE)
    end

    # Append to progress
    def append_progress(content)
      current = progress || ''
      write_file(PROGRESS_FILE, "#{current}\n#{content}")
    end

    # Read accumulated context
    def context
      read_file(CONTEXT_FILE)
    end

    # Append to context
    def append_context(content)
      current = context || ''
      write_file(CONTEXT_FILE, "#{current}\n#{content}")
    end

    # Log a session
    def log_session(session_num, content)
      filename = format('session-%03d.md', session_num)
      File.write(File.join(logs_dir, filename), content)
    end

    # Get next session number
    def next_session_number
      existing = Dir.glob(File.join(logs_dir, 'session-*.md'))
      existing.empty? ? 1 : existing.size + 1
    end

    # Check if success criteria met (Claude writes SUCCESS to state)
    def success?
      state = load_state
      state && state[:status] == 'success'
    end

    # Check if blocked
    def blocked?
      state = load_state
      state && state[:status] == "blocked"
    end

    # Get blocked reason from state notes
    def blocked_reason
      state = load_state
      return nil unless state

      state[:notes] || state[:blocked_reason] || "No reason provided"
    end

    # Build context string for Claude
    def build_context
      state = load_state || {}

      <<~CONTEXT
        # Current State

        ## Goal
        #{goal}

        ## Success Criteria
        #{criteria}

        ## Status
        - Phase: #{state[:status] || 'unknown'}
        - Current task: #{state[:current_task] || 'none'}
        - PR: #{state[:pr_number] ? "##{state[:pr_number]}" : 'none'}
        - Session: #{state[:session_count] || 0}

        ## Plan
        #{plan || '_No plan yet. Generate one first._'}

        ## Context from Previous Sessions
        #{context || '_No context yet._'}

        ## Recent Progress
        #{progress || '_No progress yet._'}
      CONTEXT
    end

    private

    def state_path
      File.join(@dir, STATE_FILE)
    end

    def logs_dir
      File.join(@dir, LOGS_DIR)
    end

    def read_file(filename)
      path = File.join(@dir, filename)
      File.exist?(path) ? File.read(path) : nil
    end

    def write_file(filename, content)
      File.write(File.join(@dir, filename), content)
    end
  end
end
