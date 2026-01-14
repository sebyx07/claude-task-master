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

    desc 'comments [PR_NUMBER]', 'Show PR review comments'
    option :actionable, type: :boolean, aliases: '-a', default: false, desc: 'Show only actionable comments'
    option :unresolved, type: :boolean, aliases: '-u', default: false, desc: 'Show only unresolved threads'
    def comments(pr_number = nil)
      state = State.new
      pastel = Pastel.new

      # Get PR number from state if not provided
      if pr_number.nil? && state.exists?
        current = state.load_state
        pr_number = current[:pr_number]
      end

      if pr_number.nil?
        puts pastel.yellow("No PR number provided and no active PR in state.")
        puts "Usage: claude-task-master comments 123"
        return
      end

      puts pastel.cyan.bold("PR ##{pr_number} Comments")
      puts

      if options[:unresolved]
        threads = GitHub.unresolved_threads(pr_number.to_i)
        if threads.empty?
          puts pastel.green("No unresolved threads!")
        else
          puts pastel.yellow("#{threads.size} unresolved thread(s):")
          threads.each do |thread|
            puts
            puts pastel.dim("  Author: #{thread[:author]}")
            puts pastel.dim("  File: #{thread[:file_path]}:#{thread[:line]}")
            puts "  #{thread[:body]&.lines&.first&.strip}"
          end
        end
      else
        all_comments = GitHub.pr_comments(pr_number.to_i)
        comments = options[:actionable] ? all_comments.select(&:actionable?) : all_comments

        if comments.empty?
          puts pastel.green(options[:actionable] ? "No actionable comments!" : "No comments!")
        else
          comments.each do |comment|
            puts severity_badge(comment.severity, pastel)
            puts pastel.dim("  #{comment.file_path}:#{comment.line_range}")
            puts pastel.dim("  Author: #{comment.author}")
            puts "  #{comment.summary || comment.body&.lines&.first&.strip}"
            puts pastel.dim("  #{comment.html_url}")
            puts
          end
        end
      end
    rescue StandardError => e
      puts pastel.red("Error fetching comments: #{e.message}")
    end

    desc 'pr [SUBCOMMAND]', 'PR management commands'
    option :number, type: :numeric, aliases: '-n', desc: 'PR number (uses current if not specified)'
    def pr(subcommand = 'status')
      state = State.new
      pastel = Pastel.new

      pr_number = options[:number]
      if pr_number.nil? && state.exists?
        current = state.load_state
        pr_number = current[:pr_number]
      end

      if pr_number.nil?
        puts pastel.yellow("No PR number provided and no active PR in state.")
        return
      end

      case subcommand
      when 'status', 'info'
        show_pr_info(pr_number, pastel)
      when 'checks', 'ci'
        show_pr_checks(pr_number, pastel)
      when 'merge'
        merge_current_pr(pr_number, pastel)
      else
        puts pastel.yellow("Unknown subcommand: #{subcommand}")
        puts "Available: status, checks, merge"
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

    def severity_badge(severity, pastel)
      case severity
      when 'critical'
        pastel.red.bold("[CRITICAL]")
      when 'warning'
        pastel.yellow.bold("[WARNING]")
      when 'major'
        pastel.magenta.bold("[MAJOR]")
      when 'trivial'
        pastel.dim("[trivial]")
      when 'nitpick'
        pastel.dim("[nitpick]")
      when 'refactor'
        pastel.blue("[refactor]")
      when 'suggestion'
        pastel.cyan("[suggestion]")
      else
        pastel.dim("[info]")
      end
    end

    def show_pr_info(pr_number, pastel)
      info = GitHub.pr_info(pr_number)

      if info.nil?
        puts pastel.red("Could not fetch PR ##{pr_number}")
        return
      end

      puts pastel.cyan.bold("PR ##{info[:number]}: #{info[:title]}")
      puts pastel.dim("State: ") + status_color(info[:state], pastel)
      puts pastel.dim("Branch: #{info[:head_ref]} -> #{info[:base_ref]}")
      puts pastel.dim("Mergeable: ") + (info[:mergeable] ? pastel.green("yes") : pastel.red("no"))
      puts pastel.dim("URL: #{info[:url]}")
    end

    def show_pr_checks(pr_number, pastel)
      status = GitHub.pr_status(pr_number)

      puts pastel.cyan.bold("CI Status: ") + ci_status_color(status[:status], pastel)
      puts

      status[:checks].each do |check|
        icon = case check[:conclusion] || check[:bucket]
               when 'success', 'pass' then pastel.green('✓')
               when 'failure', 'fail' then pastel.red('✗')
               when 'pending' then pastel.yellow('○')
               else pastel.dim('?')
               end
        puts "  #{icon} #{check[:name]}"
      end
    end

    def merge_current_pr(pr_number, pastel)
      puts pastel.yellow("Merging PR ##{pr_number}...")

      if GitHub.merge_pr(pr_number)
        puts pastel.green("PR ##{pr_number} merged successfully!")
      else
        puts pastel.red("Failed to merge PR ##{pr_number}")
      end
    end

    def ci_status_color(status, pastel)
      case status
      when :passing
        pastel.green('PASSING')
      when :failing
        pastel.red('FAILING')
      when :pending
        pastel.yellow('PENDING')
      else
        pastel.dim('UNKNOWN')
      end
    end
  end
end
