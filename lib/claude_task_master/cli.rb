# frozen_string_literal: true

require 'thor'
require 'pastel'
require 'fileutils'

module ClaudeTaskMaster
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc 'start GOAL', 'Start working on a new goal'
    long_desc <<~DESC
      Start claude-task-master with a new goal. Claude will:

      1. Analyze the codebase
      2. Create a plan in .claude-task-master/plan.md
      3. Ask for success criteria
      4. Work autonomously until done

      Examples:
        claude-task-master start "build a REST API with user auth"
        claude-task-master start "fix all TypeScript errors"
        claude-task-master start "add dark mode to the UI"
    DESC
    option :criteria, type: :string, aliases: '-c', desc: 'Success criteria (will prompt if not provided)'
    option :model, type: :string, default: 'sonnet', desc: 'Claude model to use (sonnet, opus, haiku)'
    option :no_merge, type: :boolean, default: false, desc: 'Do not auto-merge PRs (require manual merge)'
    option :max_sessions, type: :numeric, aliases: '-m', desc: 'Maximum number of sessions before stopping'
    option :pause_on_pr, type: :boolean, default: false, desc: 'Pause after creating each PR for review'
    option :verbose, type: :boolean, aliases: '-v', default: false, desc: 'Show verbose output'
    def start(goal)
      check_prerequisites!

      criteria = options[:criteria] || prompt_for_criteria

      state = State.new
      loop_opts = {
        no_merge: options[:no_merge],
        max_sessions: options[:max_sessions],
        pause_on_pr: options[:pause_on_pr],
        verbose: options[:verbose]
      }
      loop = Loop.new(state:, model: options[:model], **loop_opts)
      loop.run(goal:, criteria:)
    end

    desc 'resume', 'Resume previous work'
    long_desc <<~DESC
      Resume working from where you left off. State is loaded from
      .claude-task-master/ directory.

      Use this after:
      - Pressing Ctrl+C to pause
      - Restarting your terminal
      - Coming back the next day
    DESC
    option :model, type: :string, default: 'sonnet', desc: 'Claude model to use'
    option :no_merge, type: :boolean, default: false, desc: 'Do not auto-merge PRs'
    option :max_sessions, type: :numeric, aliases: '-m', desc: 'Maximum sessions before stopping'
    option :pause_on_pr, type: :boolean, default: false, desc: 'Pause after creating each PR'
    option :verbose, type: :boolean, aliases: '-v', default: false, desc: 'Show verbose output'
    def resume
      check_prerequisites!

      state = State.new
      unless state.exists?
        pastel = Pastel.new
        puts pastel.red("No existing state found in .claude-task-master/")
        puts "Run 'claude-task-master start \"your goal\"' to begin."
        exit 1
      end

      loop_opts = {
        no_merge: options[:no_merge],
        max_sessions: options[:max_sessions],
        pause_on_pr: options[:pause_on_pr],
        verbose: options[:verbose]
      }
      loop = Loop.new(state:, model: options[:model], **loop_opts)
      loop.resume
    end

    desc 'status', 'Show current status'
    def status
      state = State.new
      pastel = Pastel.new

      unless state.exists?
        puts pastel.yellow("No active task. Run 'claude-task-master start \"goal\"' to begin.")
        return
      end

      current = state.load_state

      puts pastel.cyan.bold("claude-task-master status")
      puts
      puts "Goal: #{state.goal}"
      puts "Criteria: #{state.criteria}"
      puts
      puts "Status: #{status_color(current[:status], pastel)}"
      puts "Current task: #{current[:current_task] || 'none'}"
      puts "PR: #{current[:pr_number] ? "##{current[:pr_number]}" : 'none'}"
      puts "Sessions: #{current[:session_count]}"
      puts "Started: #{current[:started_at]}"
      puts "Updated: #{current[:updated_at]}"
      puts
      puts "State dir: #{state.dir}"
    end

    desc 'plan', 'Show the current plan'
    def plan
      state = State.new
      pastel = Pastel.new

      unless state.exists?
        puts pastel.yellow("No active task.")
        return
      end

      plan_content = state.plan
      if plan_content
        puts plan_content
      else
        puts pastel.yellow("No plan yet. Run 'claude-task-master resume' to generate one.")
      end
    end

    desc 'logs', 'Show session logs'
    option :session, type: :numeric, aliases: '-s', desc: 'Specific session number'
    option :last, type: :numeric, aliases: '-l', default: 1, desc: 'Show last N sessions'
    def logs
      state = State.new
      pastel = Pastel.new

      unless state.exists?
        puts pastel.yellow("No active task.")
        return
      end

      logs_dir = File.join(state.dir, 'logs')
      log_files = Dir.glob(File.join(logs_dir, 'session-*.md')).sort

      if options[:session]
        filename = format('session-%03d.md', options[:session])
        path = File.join(logs_dir, filename)
        if File.exist?(path)
          puts File.read(path)
        else
          puts pastel.red("Session #{options[:session]} not found.")
        end
      else
        log_files.last(options[:last]).each do |path|
          puts pastel.cyan("=== #{File.basename(path)} ===")
          puts File.read(path)
          puts
        end
      end
    end

    desc 'version', 'Show version'
    def version
      puts "claude-task-master #{VERSION}"
    end

    desc 'doctor', 'Check prerequisites and system health'
    def doctor
      pastel = Pastel.new
      all_good = true

      puts pastel.cyan.bold("claude-task-master doctor")
      puts

      # Check Claude CLI
      print "Claude CLI: "
      if Claude.available?
        version = Claude.version
        puts pastel.green("#{version}")
      else
        puts pastel.red("NOT FOUND")
        puts pastel.dim("  Install: npm install -g @anthropic-ai/claude-code")
        all_good = false
      end

      # Check gh CLI
      print "GitHub CLI: "
      gh_version = `gh --version 2>&1`.split("\n").first rescue nil
      if gh_version
        puts pastel.green(gh_version)
      else
        puts pastel.red("NOT FOUND")
        puts pastel.dim("  Install: https://cli.github.com/")
        all_good = false
      end

      # Check gh auth
      print "GitHub Auth: "
      if GitHub.available?
        puts pastel.green("authenticated")
      else
        puts pastel.yellow("NOT AUTHENTICATED")
        puts pastel.dim("  Run: gh auth login")
        all_good = false
      end

      # Check git
      print "Git: "
      git_version = `git --version 2>&1`.strip rescue nil
      if git_version
        puts pastel.green(git_version)
      else
        puts pastel.red("NOT FOUND")
        all_good = false
      end

      # Check Ruby version
      print "Ruby: "
      if RUBY_VERSION >= '3.1.0'
        puts pastel.green("#{RUBY_VERSION}")
      else
        puts pastel.yellow("#{RUBY_VERSION} (recommend 3.1+)")
      end

      # Check current repo
      print "Git repo: "
      if system('git rev-parse --git-dir > /dev/null 2>&1')
        repo = GitHub.current_repo
        puts pastel.green(repo || 'local repo')
      else
        puts pastel.yellow("not in a git repository")
      end

      # Check for CLAUDE.md
      print "CLAUDE.md: "
      if File.exist?('CLAUDE.md')
        puts pastel.green("present")
      else
        puts pastel.dim("not found (optional)")
      end

      # Check for existing state
      print "State dir: "
      state = State.new
      if state.exists?
        current = state.load_state
        puts pastel.cyan("exists (status: #{current[:status]})")
      else
        puts pastel.dim("none")
      end

      puts
      if all_good
        puts pastel.green.bold("All prerequisites met!")
      else
        puts pastel.red.bold("Some prerequisites missing. Fix them before running.")
        exit 1
      end
    end

    desc 'clean', 'Remove state directory and start fresh'
    option :force, type: :boolean, aliases: '-f', default: false, desc: 'Skip confirmation'
    def clean
      state = State.new
      pastel = Pastel.new

      unless state.exists?
        puts pastel.yellow("No state directory to clean.")
        return
      end

      unless options[:force]
        puts pastel.yellow("This will delete .claude-task-master/ and all session data.")
        print "Are you sure? (y/N) "
        response = $stdin.gets.chomp.downcase
        unless response == 'y' || response == 'yes'
          puts "Aborted."
          return
        end
      end

      FileUtils.rm_rf(state.dir)
      puts pastel.green("Cleaned up .claude-task-master/")
    end

    desc 'context', 'Show or edit the context file'
    def context
      state = State.new
      pastel = Pastel.new

      unless state.exists?
        puts pastel.yellow("No active task.")
        return
      end

      context_path = File.join(state.dir, 'context.md')
      if File.exist?(context_path)
        puts File.read(context_path)
      else
        puts pastel.dim("No context file yet.")
      end
    end

    desc 'progress', 'Show the progress log'
    def progress
      state = State.new
      pastel = Pastel.new

      unless state.exists?
        puts pastel.yellow("No active task.")
        return
      end

      progress_path = File.join(state.dir, 'progress.md')
      if File.exist?(progress_path)
        puts File.read(progress_path)
      else
        puts pastel.dim("No progress log yet.")
      end
    end

    # Default command (no args = resume or show help)
    default_task :default_action

    desc 'default_action', 'Default action', hide: true
    def default_action
      state = State.new
      if state.exists?
        invoke :resume
      else
        invoke :help
      end
    end

    private

    def check_prerequisites!
      pastel = Pastel.new

      unless Claude.available?
        puts pastel.red("Claude CLI not found. Install it first:")
        puts "  npm install -g @anthropic-ai/claude-code"
        exit 1
      end

      unless GitHub.available?
        puts pastel.yellow("Warning: gh CLI not authenticated. PR features won't work.")
        puts "  Run: gh auth login"
      end
    end

    def prompt_for_criteria
      pastel = Pastel.new
      puts pastel.cyan("What are your success criteria?")
      puts pastel.dim("(e.g., 'tests pass, deploys to staging, no sentry errors for 10min')")
      print "> "
      $stdin.gets.chomp
    end

    def status_color(status, pastel)
      case status
      when 'success'
        pastel.green(status)
      when 'blocked'
        pastel.red(status)
      when 'ready', 'working'
        pastel.cyan(status)
      when 'planning'
        pastel.yellow(status)
      else
        status
      end
    end
  end
end
