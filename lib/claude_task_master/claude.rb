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
    def self.planning_prompt(goal, existing_claude_md: nil, no_merge: false)
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
        # Claude Task Master - Planning Phase

        You are an autonomous software engineer starting a new project. Your job is to:
        1. **Analyze the codebase** - Understand what exists, patterns, tech stack
        2. **Create a detailed plan** - Break the goal into PRs, each PR into tasks
        3. **Save the plan** - Write to .claude-task-master/plan.md

        #{claude_md_section}

        ## Goal
        #{goal}

        ## Planning Instructions

        ### Step 1: Explore the Codebase
        - Read key files: README.md, CLAUDE.md, package.json/Gemfile/Cargo.toml/CMakeLists.txt
        - Understand the project structure and directory layout
        - Identify existing patterns, coding style, and conventions
        - Note the tech stack, dependencies, and build system
        - Check for existing CI/CD configuration (.github/workflows, etc.)

        ### Step 2: Design the Plan
        Create a plan structured as multiple PRs. Each PR should be:
        - **Atomic**: A logical chunk of work that makes sense on its own
        - **Reviewable**: Small enough for meaningful code review
        - **Testable**: Includes tests or can be verified independently

        Structure your plan like this:
        ```markdown
        # Plan for: [Goal Summary]

        ## PR 1: [Title - e.g., "Project Foundation"]
        - [ ] Task 1.1: Description
        - [ ] Task 1.2: Description
        ...

        ## PR 2: [Title - e.g., "Core Implementation"]
        - [ ] Task 2.1: Description
        ...
        ```

        Guidelines:
        - 3-10 PRs typically, depending on scope
        - 3-15 tasks per PR
        - First PR often includes: project setup, CI, basic structure
        - Order tasks by dependency (what must be done first)
        - Include test tasks where appropriate
        - Include documentation where appropriate

        ### Step 3: Write State Files
        1. Write plan to `.claude-task-master/plan.md`
        2. Update `.claude-task-master/state.json`:
           - Set `status` to `"ready"`
           - Set `current_task` to first task description
           - Set `current_pr` to `1`
        3. Write context to `.claude-task-master/context.md`:
           - Key files discovered
           - Patterns to follow
           - Decisions made

        Be thorough but practical. Each PR should deliver value.
      PROMPT
    end

    # Build the work prompt
    def self.work_prompt(context, no_merge: false)
      merge_instructions = if no_merge
                             <<~MERGE
                               **IMPORTANT: DO NOT MERGE PRs**
                               - Create PRs but do not merge them
                               - Wait for manual review and merge
                               - Once PR is ready (CI green, no unresolved comments), move to next PR
                               - Set `pr_ready` to `true` in state.json when ready for merge
                             MERGE
                           else
                             <<~MERGE
                               **Auto-merge is enabled**
                               - Once PR is approved (CI green, no unresolved comments), merge it:
                                 `gh pr merge --squash --delete-branch`
                               - After merge, pull main and start next PR
                             MERGE
                           end

      <<~PROMPT
        # Claude Task Master - Work Session

        You are an autonomous software engineer continuing work on a project.

        ## Current State
        #{context}

        ## Work Loop Instructions

        ### Step 1: Understand Current State
        - Read `.claude-task-master/plan.md` to see all tasks
        - Read `.claude-task-master/state.json` for current task and status
        - Identify what needs to be done next

        ### Step 2: Execute the Work

        **If working on a task:**
        1. Implement the task (write code, create files)
        2. Run tests/linters if available
        3. Commit with a clear message
        4. Check off task in plan.md: `- [x] Task`
        5. Update state.json with next task
        6. Continue to next task in same PR

        **If PR is ready (all tasks for this PR done):**
        1. Create the PR if not already created:
           ```bash
           gh pr create --title "PR Title" --body "Description"
           ```
        2. Store PR number in state.json: `pr_number`

        **If PR exists, check its status:**
        1. Check CI status:
           ```bash
           gh pr checks
           ```
        2. Check for review comments (CodeRabbit, Copilot, human reviewers):
           ```bash
           gh pr view --json comments,reviews
           gh api repos/{owner}/{repo}/pulls/{pr}/comments
           ```
        3. **CRITICAL: Address ALL review comments before proceeding**
           - Read each comment carefully
           - Make the requested changes
           - Commit and push: `git push`
           - Wait for CI to pass again

        **If CI fails:**
        1. Read the error output: `gh pr checks`
        2. Fix the issues
        3. Commit and push
        4. Repeat until green

        **If review comments exist:**
        1. Address each comment
        2. Push fixes
        3. Comments from bots (CodeRabbit, Copilot) often auto-resolve
        4. Check again: `gh api repos/{owner}/{repo}/pulls/{pr}/comments`

        #{merge_instructions}

        ### Step 3: Track Progress

        Always update state files after significant progress:

        **plan.md:**
        - Check off completed tasks: `- [x] Task done`
        - Keep unchecked tasks: `- [ ] Task pending`

        **state.json:**
        ```json
        {
          "status": "working|ready|blocked|success",
          "current_task": "Current task description",
          "current_pr": 1,
          "pr_number": 123,
          "pr_ready": false,
          "session_count": N,
          "updated_at": "ISO timestamp"
        }
        ```

        **progress.md:**
        - Append notes about what was done
        - Document any issues encountered
        - Note decisions made

        **context.md:**
        - Add newly discovered patterns
        - Document learnings about the codebase

        ### Step 4: Handle Completion

        **When current PR is complete (merged or ready):**
        1. Update state.json: increment `current_pr`
        2. Create new branch from main: `git checkout main && git pull && git checkout -b pr-N-description`
        3. Reset `pr_number` to null in state.json
        4. Continue with next PR's tasks

        **When ALL PRs are done:**
        1. Set status to `"success"` in state.json
        2. Write completion summary to progress.md

        **If stuck or blocked:**
        1. Set status to `"blocked"` in state.json
        2. Explain the blocker clearly in progress.md
        3. Do NOT retry the same failing approach repeatedly

        ### Guidelines
        - Work autonomously - make decisions
        - Ship working code - don't over-engineer
        - Follow existing patterns in the codebase
        - Write tests where appropriate
        - Keep commits focused and well-described
        - Don't leave commented-out code
        - Fix issues properly, don't hack around them
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
