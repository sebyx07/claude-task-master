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

### Running Tests

```bash
bundle exec rspec
```

Tests use fixtures and mocked Claude calls. No real API calls in tests.

### Test Structure

```
spec/
├── spec_helper.rb           # RSpec config + SimpleCov setup
├── support/
│   ├── temp_directory.rb    # Shared context for temp dirs
│   ├── github_api_mocks.rb  # WebMock helpers for GitHub API
│   └── claude_cli_mocks.rb  # Helpers for mocking claude CLI
├── fixtures/
│   ├── github_api/          # Sample GitHub API responses
│   ├── state_files/         # Sample .claude-task-master files
│   └── claude_output/       # Sample Claude CLI output
└── claude_task_master/
    ├── state_spec.rb        # State management tests
    ├── claude_spec.rb       # Claude CLI wrapper tests
    ├── github_spec.rb       # GitHub integration tests
    ├── loop_spec.rb         # Main loop tests
    ├── cli_spec.rb          # CLI command tests
    └── pr_comment_spec.rb   # PR comment model tests
```

### Testing Approach

**Mocking Strategy:**
- **GitHub API**: WebMock stubs all Octokit calls, fixtures in `spec/fixtures/github_api/`
- **Claude CLI**: Mock `Open3.popen2e` to avoid real CLI invocations
- **File I/O**: Use temporary directories (cleaned up after each test)
- **External commands**: Mock `gh` CLI, `git` commands where needed

**Coverage Goals:**
- Overall: 80%+
- Core modules (State, Claude): 90%+
- Integrations (GitHub): 85%+
- Models (PRComment): 95%+
- CLI/Loop: 80%+

**Shared Contexts:**
- `:temp_dir` - Creates temporary directory, changes into it for test
- `:github_api` - Enables WebMock, provides GitHub API stub helpers
- `:claude_cli` - Provides helpers for mocking Claude CLI calls

**Example Test:**

```ruby
require "spec_helper"

RSpec.describe ClaudeTaskMaster::State, :temp_dir do
  it "initializes state directory" do
    state = described_class.new

    expect(File.directory?(".claude-task-master")).to be true
    expect(File.directory?(".claude-task-master/logs")).to be true
  end
end
```

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
