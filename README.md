# claude-task-master

Autonomous task loop for Claude Code. Keep Claude working until the job is done.

## The Loop

```
plan → work → check → work → check → ... → done
```

Claude does the work AND the checking. The task master just keeps the loop going.

## Quick Start

```bash
# Install
gem install claude-task-master

# Start a new task
claude-task-master start "build a REST API with user authentication"

# Enter success criteria when prompted:
> tests pass, PR merged, no sentry errors for 10 minutes

# Let it run. Come back later.
# Press Ctrl+C to pause anytime.

# Resume
claude-task-master resume
# Or just:
claude-task-master
```

## How It Works

1. **Planning Phase**: Claude analyzes your codebase, creates a plan with tasks
2. **Work Loop**: Claude implements tasks one by one
3. **PR Cycle**: Create PR → wait for CI → fix review comments → repeat → merge
4. **Success Check**: Verifies success criteria are met
5. **Next Task**: Moves to next task until all done

All state persists in `.claude-task-master/` so you can:
- Pause and resume anytime
- Inspect progress in human-readable files
- Kill and restart without losing work

## Commands

```bash
# Start fresh
claude-task-master start "your goal here"

# Resume previous work
claude-task-master resume
claude-task-master  # shorthand

# Check status
claude-task-master status

# View the plan
claude-task-master plan

# View session logs
claude-task-master logs
claude-task-master logs --last 3
claude-task-master logs --session 5

# View context/progress
claude-task-master context
claude-task-master progress

# Clean up and start fresh
claude-task-master clean
claude-task-master clean -f  # skip confirmation

# Check prerequisites
claude-task-master doctor
```

## Options

```bash
# Use different model
claude-task-master start "goal" --model opus

# Provide criteria inline
claude-task-master start "goal" --criteria "tests pass, deploys to staging"

# Don't auto-merge PRs (require manual review and merge)
claude-task-master start "goal" --no-merge

# Limit number of work sessions
claude-task-master start "goal" --max-sessions 10
claude-task-master resume -m 5  # shorthand

# Pause after creating each PR for review
claude-task-master start "goal" --pause-on-pr

# Verbose output
claude-task-master start "goal" --verbose

# Combine options
claude-task-master start "goal" --no-merge --max-sessions 20 --model opus
```

## State Directory

Everything lives in `.claude-task-master/`:

```
.claude-task-master/
├── goal.txt          # What you asked for
├── criteria.txt      # Success criteria
├── plan.md           # Tasks with checkboxes
├── state.json        # Machine state
├── progress.md       # Human-readable progress
├── context.md        # Learnings across sessions
└── logs/
    └── session-*.md  # Full log per Claude invocation
```

## Works With Any Review System

The task master is agnostic to code review tools:

- **CodeRabbit** - Detects comments from `coderabbitai[bot]`
- **GitHub Copilot** - Detects suggestions and reviews
- **Human reviewers** - Claude reads and addresses any PR comments
- **Generic** - Any comment on the PR gets attention

Claude reads the comments and decides what to fix. The harness just reports.

## Requirements

- Ruby 3.1+
- [Claude Code CLI](https://claude.ai/code) (`npm install -g @anthropic-ai/claude-code`)
- [GitHub CLI](https://cli.github.com/) (`gh`) - for PR features
- `--dangerously-skip-permissions` - only use in trusted environments

## How It Calls Claude

```bash
claude -p \
  --dangerously-skip-permissions \
  --model sonnet \
  "Your context and instructions here"
```

Each invocation is independent. State persists via files.

## Example Session

```
$ claude-task-master start "add user authentication to the API"
Starting claude-task-master...
Goal: add user authentication to the API

What are your success criteria?
(e.g., 'tests pass, deploys to staging, no sentry errors for 10min')
> tests pass, PR merged

Phase 1: Planning...
....................
Plan created. Check .claude-task-master/plan.md

Phase 2: Working...
Press Ctrl+C to pause (can resume later)

[Session 1] Working on: Set up authentication dependencies
  Completed in 45.2s

[Session 2] Working on: Create user model and migrations
  Completed in 89.1s
  PR created: #42

[Session 3] Working on: Fix CodeRabbit comments
  Completed in 32.5s

[Session 4] Working on: Address remaining review feedback
  Completed in 28.3s

[Session 5] Working on: Merge and verify
  Completed in 15.0s

SUCCESS!
All tasks completed. Check .claude-task-master/progress.md
```

## Development

```bash
git clone https://github.com/developerz-ai/claude-task-master
cd claude-task-master
bundle install

# Run locally
bundle exec bin/claude-task-master start "test goal"

# Run tests
bundle exec rspec
```

## Philosophy

Claude is smart. It can:
- Read code and understand patterns
- Make decisions about implementation
- Create PRs and fix review comments
- Know when it's done

The task master just:
- Keeps calling Claude
- Persists state between calls
- Detects success/blocked

That's it. ~300 lines of Ruby. Claude does the thinking.

## License

MIT
