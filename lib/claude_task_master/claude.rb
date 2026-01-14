# frozen_string_literal: true

require 'open3'
require 'timeout'

module ClaudeTaskMaster
  # Wrapper around the Claude Code CLI
  # Handles invocation, output capture, and error handling
  class Claude
    DEFAULT_TIMEOUT = 3600 # 1 hour max per invocation
    CLAUDE_BINARY = 'claude'

    attr_reader :model, :timeout

    def initialize(model: 'sonnet', timeout: DEFAULT_TIMEOUT)
      @model = model
      @timeout = timeout
    end

    # Check if Claude CLI is available
    def self.available?
      system('which claude > /dev/null 2>&1')
    end

    # Get Claude version
    def self.version
      `claude --version 2>&1`.strip
    end

    # Invoke Claude with a prompt (non-interactive mode)
    # Returns [success, output, exit_code]
    def invoke(prompt, allowed_tools: nil, working_dir: nil)
      args = build_args(allowed_tools)
      cmd = [CLAUDE_BINARY, *args, prompt]

      output = +''
      success = false
      exit_code = nil

      Dir.chdir(working_dir || Dir.pwd) do
        Timeout.timeout(timeout) do
          Open3.popen2e(*cmd) do |stdin, stdout_err, wait_thr|
            stdin.close

            # Stream output in real-time
            stdout_err.each_line do |line|
              output << line
              # Minimal progress indicator
              $stdout.print '.' if line.include?('[Tool:')
            end

            exit_code = wait_thr.value.exitstatus
            success = exit_code.zero?
          end
        end
      end

      $stdout.puts if output.include?('[Tool:') # Newline after dots

      [success, output, exit_code]
    rescue Timeout::Error
      [false, "#{output}\n\n[TIMEOUT after #{timeout}s]", -1]
    rescue StandardError => e
      [false, "#{output}\n\n[ERROR: #{e.message}]", -1]
    end

    # Build the planning prompt
    def self.planning_prompt(goal, existing_claude_md: nil)
      claude_md_section = if existing_claude_md
                            <<~SECTION
                              ## Existing Project Context (CLAUDE.md)
                              The project already has a CLAUDE.md file. Read and follow its conventions:

                              ```
                              #{existing_claude_md[0..2000]}#{'...' if existing_claude_md.length > 2000}
                              ```
                            SECTION
                          else
                            ''
                          end

      <<~PROMPT
        You are starting work on a new goal. Your job is to:

        1. **Analyze the codebase** - Understand what exists, the structure, patterns
        2. **Create a plan** - Break the goal into concrete tasks with checkboxes
        3. **Save the plan** - Write to .claude-task-master/plan.md

        #{claude_md_section}

        ## Goal
        #{goal}

        ## Instructions

        1. First, explore the codebase:
           - Read key files (README, package.json/Gemfile/Cargo.toml, etc.)
           - Understand the project structure
           - Note any existing patterns or conventions

        2. Then create a plan:
           - Break down the goal into 5-20 concrete tasks
           - Use checkbox format: `- [ ] Task description`
           - Order tasks by dependency (what must be done first)
           - Include testing/verification steps

        3. Write the plan to `.claude-task-master/plan.md`

        4. Update `.claude-task-master/state.json`:
           - Set status to "ready"
           - Set current_task to the first task

        5. Write initial context to `.claude-task-master/context.md`:
           - Note key files and patterns discovered
           - Any important decisions or assumptions

        Be thorough but practical. The plan should be achievable.
      PROMPT
    end

    # Build the work prompt
    def self.work_prompt(context)
      <<~PROMPT
        You are continuing work on a project. Here is your current state:

        #{context}

        ## Instructions

        1. **Read the plan** from `.claude-task-master/plan.md`
        2. **Pick the next unchecked task** (or continue current if in progress)
        3. **Do the work**:
           - Write code, create files, run tests
           - Create a PR if ready: `gh pr create`
           - Check CI: `gh pr checks --watch`
           - Check for review comments: `gh pr view --json comments,reviews`
           - Fix any issues, push, repeat until clean

        4. **Update state files**:
           - Check off completed tasks in `plan.md`: `- [x] Task`
           - Update `state.json` with current status and task
           - Append learnings to `context.md`
           - Append progress notes to `progress.md`

        5. **When a task is fully done** (PR merged, CI green, no comments):
           - Mark it complete in plan.md
           - Move to next task
           - Update state.json

        6. **When ALL tasks are done**:
           - Set status to "success" in state.json
           - Write final summary to progress.md

        7. **If you get stuck**:
           - Set status to "blocked" in state.json
           - Explain the blocker in progress.md
           - Don't keep retrying the same failing approach

        Work autonomously. Make decisions. Ship code.
      PROMPT
    end

    private

    def build_args(allowed_tools)
      args = [
        '-p',
        '--dangerously-skip-permissions',
        '--model', model
      ]

      if allowed_tools
        args += ['--allowedTools', allowed_tools.join(',')]
      end

      args
    end
  end
end
