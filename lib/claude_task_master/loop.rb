# frozen_string_literal: true

require 'pastel'

module ClaudeTaskMaster
  # The main work loop
  # Keeps calling Claude until success criteria met
  class Loop
    attr_reader :state, :claude, :pastel

    def initialize(state:, model: 'sonnet')
      @state = state
      @claude = Claude.new(model:)
      @pastel = Pastel.new
    end

    # Run the full loop from start
    def run(goal:, criteria:)
      puts pastel.cyan("Starting claude-task-master...")
      puts pastel.dim("Goal: #{goal[0..100]}#{'...' if goal.length > 100}")
      puts

      # Initialize state
      state.init(goal:, criteria:)

      # Phase 1: Planning
      plan_phase

      # Phase 2: Work loop
      work_loop
    end

    # Resume from existing state
    def resume
      unless state.exists?
        raise ConfigError, 'No existing state found. Start fresh with a goal.'
      end

      current_state = state.load_state
      puts pastel.cyan("Resuming claude-task-master...")
      puts pastel.dim("Goal: #{state.goal[0..100]}#{'...' if state.goal.length > 100}")
      puts pastel.dim("Status: #{current_state[:status]}")
      puts pastel.dim("Session: #{current_state[:session_count]}")
      puts

      if current_state[:status] == 'planning'
        plan_phase
      end

      work_loop
    end

    private

    # Phase 1: Generate plan
    def plan_phase
      puts pastel.yellow("Phase 1: Planning...")

      # Check for existing CLAUDE.md
      claude_md_path = File.join(Dir.pwd, 'CLAUDE.md')
      existing_claude_md = File.exist?(claude_md_path) ? File.read(claude_md_path) : nil

      prompt = Claude.planning_prompt(state.goal, existing_claude_md:)

      session_num = state.next_session_number
      state.update_state(session_count: session_num)

      success, output, _exit_code = claude.invoke(prompt)

      # Log the session
      state.log_session(session_num, "# Planning Session\n\n#{output}")

      unless success
        state.update_state(status: 'blocked')
        state.append_progress("\n## Blocked in Planning\n\n#{output[-500..]}")
        raise ClaudeError, 'Planning failed. Check logs.'
      end

      current = state.load_state
      if current[:status] != 'ready'
        # Claude didn't update state, do it ourselves
        state.update_state(status: 'ready')
      end

      puts pastel.green("Plan created. Check .claude-task-master/plan.md")
      puts
    end

    # Show current PR status (CI, comments)
    def show_pr_status(pr_number)
      ci_status = GitHub.pr_status(pr_number)
      unresolved = GitHub.unresolved_threads(pr_number)

      status_icon = case ci_status[:status]
                    when :passing then pastel.green('CI passing')
                    when :failing then pastel.red('CI failing')
                    when :pending then pastel.yellow('CI pending')
                    else pastel.dim('CI unknown')
                    end

      comments_text = if unresolved.empty?
                        pastel.green('0 unresolved')
                      else
                        pastel.yellow("#{unresolved.size} unresolved comments")
                      end

      puts pastel.dim("  PR ##{pr_number}: #{status_icon} | #{comments_text}")
    rescue StandardError => e
      # Don't fail if we can't get PR status
      puts pastel.dim("  PR ##{pr_number}: (couldn't fetch status)")
    end

    # Phase 2: Work until done
    def work_loop
      puts pastel.yellow("Phase 2: Working...")
      puts pastel.dim("Press Ctrl+C to pause (can resume later)")
      puts

      loop do
        # Check if done
        if state.success?
          puts
          puts pastel.green.bold("SUCCESS!")
          puts pastel.green("All tasks completed. Check .claude-task-master/progress.md")
          break
        end

        if state.blocked?
          puts
          puts pastel.red.bold("BLOCKED")
          puts pastel.red("Claude got stuck. Check .claude-task-master/progress.md for details.")
          break
        end

        # Run one work iteration
        work_iteration

        # Brief pause between iterations
        sleep 2
      end
    rescue Interrupt
      puts
      puts pastel.yellow("Paused. Run 'claude-task-master' to resume.")
      state.append_progress("\n_Paused at #{Time.now.iso8601}_\n")
    end

    # Single work iteration
    def work_iteration
      current_state = state.load_state
      session_num = state.next_session_number

      # Show PR/CI status if we have a PR
      if current_state[:pr_number]
        show_pr_status(current_state[:pr_number])
      end

      puts pastel.cyan("[Session #{session_num}] Working on: #{current_state[:current_task] || 'next task'}")

      # Build context and prompt
      context = state.build_context
      prompt = Claude.work_prompt(context)

      # Update session count
      state.update_state(session_count: session_num)

      # Invoke Claude
      start_time = Time.now
      success, output, _exit_code = claude.invoke(prompt)
      duration = (Time.now - start_time).round(1)

      # Log the session
      log_content = <<~LOG
        # Work Session #{session_num}

        _Duration: #{duration}s_
        _Started: #{start_time.iso8601}_

        ## Output

        #{output}
      LOG
      state.log_session(session_num, log_content)

      # Report
      if success
        puts pastel.green("  Completed in #{duration}s")
      else
        puts pastel.red("  Session ended with error (#{duration}s)")
        state.append_progress("\n## Session #{session_num} Error\n\n#{output[-500..]}")
      end

      # Check new state
      new_state = state.load_state
      if new_state[:current_task] != current_state[:current_task]
        puts pastel.dim("  Task changed: #{new_state[:current_task]}")
      end
      if new_state[:pr_number] && new_state[:pr_number] != current_state[:pr_number]
        puts pastel.dim("  PR created: ##{new_state[:pr_number]}")
      end
    end
  end
end
