# CLAUDE.md

Instructions for Claude Code when working on this repository.

## Project Overview

**claude-task-master** — Autonomous task loop for Claude Code.

A lightweight Ruby harness that keeps Claude working until success criteria are met. It's not trying to make Claude smarter—Claude is already smart. It just keeps the loop going:

```
plan → work → check → work → check → ... → done
```

## Core Philosophy

1. **Claude does the work AND the checking** - The harness just keeps calling Claude
2. **State via files** - Everything persists in `.claude-task-master/`
3. **Generic review system** - Works with CodeRabbit, Copilot, or any review tool
4. **Shift handoff pattern** - Each Claude invocation is like a new engineer taking over

## Architecture

```
bin/claude-task-master     # CLI entry point
lib/
  claude_task_master.rb    # Main require file
  claude_task_master/
    cli.rb                 # Thor CLI commands
    loop.rb                # Main work loop
    state.rb               # State management (.claude-task-master/)
    claude.rb              # Claude CLI wrapper
    github.rb              # GitHub operations (gh CLI)
    reviewers/
      base.rb              # Base reviewer interface
      coderabbit.rb        # CodeRabbit implementation
      copilot.rb           # GitHub Copilot implementation
      generic.rb           # Generic PR comment reviewer
    providers/
      ci.rb                # Generic CI status checker
      sentry.rb            # Sentry error monitoring
```

## Commands

```bash
# Start fresh with a goal
claude-task-master "build a REST API with user auth"

# Resume previous work
claude-task-master              # No args = resume
claude-task-master --resume

# Check status
claude-task-master status
```

## State Directory

All state lives in `.claude-task-master/` within the project:

```
.claude-task-master/
├── goal.txt              # What we're building
├── criteria.txt          # Success criteria
├── plan.md               # Generated plan with [ ]/[x] checkboxes
├── state.json            # Machine state (current task, PR #, etc.)
├── progress.md           # Human-readable progress notes
├── context.md            # Accumulated learnings (fed to Claude)
└── logs/
    ├── session-001.md    # Full log per Claude invocation
    └── session-002.md
```

## The Loop

```ruby
# Pseudocode - this is the entire thing
def run
  setup_or_resume

  loop do
    # Build context from state files
    context = build_context

    # Call Claude with full autonomy
    invoke_claude(context)

    # Check if done
    break if success_criteria_met?

    # Brief pause between invocations
    sleep 2
  end

  puts "Done!"
end
```

## Claude Invocation

Each Claude call gets:
1. The goal and success criteria
2. Current state (what task we're on, PR status, etc.)
3. Context from previous sessions
4. Instructions to update state files when done

```bash
claude -p \
  --dangerously-skip-permissions \
  --allowedTools "Bash,Edit,Read,Write,Glob,Grep" \
  "#{context_and_instructions}"
```

## Review System

The harness is agnostic to review tools. It checks:

1. **CI status**: `gh pr checks --watch` (waits for completion)
2. **Review comments**: Fetches PR comments, filters by reviewer
3. **Unresolved threads**: Uses GitHub GraphQL for resolution status

Claude reads comments and decides what to fix. The harness just reports.

## Key Files

### cli.rb
Thor CLI with commands: `start`, `resume`, `status`

### loop.rb
Main loop logic. Calls Claude repeatedly until done.

### state.rb
Reads/writes `.claude-task-master/` files. Handles resume.

### claude.rb
Wrapper around `claude` CLI. Builds prompts, captures output.

### github.rb
GitHub operations via `gh` CLI:
- Create PR: `gh pr create`
- Check CI: `gh pr checks`
- Get comments: `gh api repos/:owner/:repo/pulls/:pr/comments`
- Merge: `gh pr merge`

### reviewers/base.rb
Interface for review systems:
```ruby
class Base
  def fetch_comments(pr_number) = raise NotImplementedError
  def unresolved_comments(pr_number) = raise NotImplementedError
  def resolve_comment(comment_id) = raise NotImplementedError
end
```

## Code Style

- Ruby 3.1+
- Single Responsibility Principle (SRP) - each file does one thing
- No metaprogramming magic
- Explicit over implicit
- Files under 200 lines

## Testing

```bash
bundle exec rspec
```

Tests use fixtures and mocked Claude calls. No real API calls in tests.

## Development

```bash
# Install dependencies
bundle install

# Run locally
bundle exec bin/claude-task-master "test goal"

# Run tests
bundle exec rspec

# Lint
bundle exec rubocop
```

## Security

- Uses `--dangerously-skip-permissions` - only run in trusted environments
- No credentials stored in state files
- Uses `gh` CLI for auth (inherits user's GitHub auth)
