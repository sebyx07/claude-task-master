# frozen_string_literal: true

module ClaudeTaskMaster
  class Error < StandardError; end
  class ConfigError < Error; end
  class ClaudeError < Error; end

  STATE_DIR = ".claude-task-master"
end

require_relative "claude_task_master/version"
require_relative "claude_task_master/state"
require_relative "claude_task_master/claude"
require_relative "claude_task_master/pr_comment"
require_relative "claude_task_master/github"
require_relative "claude_task_master/loop"
require_relative "claude_task_master/cli"
