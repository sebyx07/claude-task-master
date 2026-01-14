# frozen_string_literal: true

module ClaudeTaskMaster
  # Represents a GitHub PR review comment
  # Detects CodeRabbit, Copilot, and other review bot comments
  class PRComment
    ACTIONABLE_SEVERITIES = %w[major critical warning].freeze

    # Known bot authors
    CODERABBIT_BOT = "coderabbitai[bot]"
    COPILOT_BOT = "github-copilot[bot]"
    KNOWN_BOTS = [CODERABBIT_BOT, COPILOT_BOT].freeze

    attr_reader :id, :file_path, :line, :start_line, :body, :author,
                :created_at, :updated_at, :html_url, :resolved

    def initialize(attrs = {})
      @id = attrs[:id] || attrs["id"]
      @file_path = attrs[:path] || attrs["path"]
      @line = attrs[:line] || attrs["line"]
      @start_line = attrs[:start_line] || attrs["start_line"]
      @body = attrs[:body] || attrs["body"]
      @author = extract_author(attrs[:user] || attrs["user"])
      @created_at = attrs[:created_at] || attrs["created_at"]
      @updated_at = attrs[:updated_at] || attrs["updated_at"]
      @html_url = attrs[:html_url] || attrs["html_url"]
      @resolved = attrs[:resolved] || attrs["resolved"]
    end

    # Create collection from API response
    def self.from_api_response(data)
      data = [data] unless data.is_a?(Array)
      data.map { |item| new(item) }
    end

    # Line range as string (e.g., "40-42" or "42")
    def line_range
      @line_range ||= begin
        start = start_line || line
        start == line ? line.to_s : "#{start}-#{line}"
      end
    end

    # Parse severity from CodeRabbit/Copilot comment body
    def severity
      @severity ||= parse_severity
    end

    # Extract summary from comment body
    def summary
      @summary ||= extract_summary
    end

    # Check if comment requires attention
    def actionable?
      ACTIONABLE_SEVERITIES.include?(severity)
    end

    # Bot detection
    def from_coderabbit?
      author == CODERABBIT_BOT
    end

    def from_copilot?
      author == COPILOT_BOT
    end

    def from_bot?
      KNOWN_BOTS.include?(author) || author&.end_with?("[bot]")
    end

    def from_human?
      !from_bot?
    end

    # Resolved status
    def resolved?
      @resolved == true
    end

    def unresolved?
      @resolved == false
    end

    # Check if comment has committable suggestion
    def suggestion?
      body&.include?("```suggestion") || false
    end

    # Extract suggestion code from body
    def suggestion_code
      @suggestion_code ||= if body.nil? || !body.include?("```suggestion")
                             nil
                           else
                             match = body.match(/```suggestion[^\n]*\n(.*?)\n```/m)
                             match ? match[1] : nil
                           end
    end

    # Serialize to hash
    def to_h
      {
        id: id,
        file_path: file_path,
        line_range: line_range,
        author: author,
        severity: severity,
        summary: summary,
        actionable: actionable?,
        from_bot: from_bot?,
        resolved: resolved?,
        has_suggestion: suggestion?,
        html_url: html_url
      }
    end

    private

    def extract_author(user)
      return user if user.is_a?(String)
      return nil unless user

      user[:login] || user["login"]
    end

    def parse_severity
      return "info" unless body

      case body
      when /❌.*Critical/m, /\*\*Critical\*\*/i
        "critical"
      when /⚠️.*Warning/m, /\*\*Warning\*\*/i
        "warning"
      when /🟠 Major/m, /\*\*Major\*\*/i
        "major"
      when /🔵 Trivial/m, /\*\*Trivial\*\*/i
        "trivial"
      when /🛠️ Refactor/m, /refactor suggestion/i
        "refactor"
      when /🧹 Nitpick/m, /nitpick/i
        "nitpick"
      when /suggestion:/i, /consider:/i
        "suggestion"
      else
        "info"
      end
    end

    def extract_summary
      return nil unless body

      # Try to extract bolded summary line
      match = body.match(/\*\*(.+?)\*\*/)
      return match[1] if match

      # Fallback to first non-empty line, skipping metadata
      line = body.lines.reject { |l| l.strip.empty? || l.strip.start_with?("_", "<", "<!--") }.first
      line&.strip&.truncate(100)
    end
  end
end

# Monkey-patch String for truncate
class String
  def truncate(max_length, omission: "...")
    return self if length <= max_length

    "#{self[0, max_length - omission.length]}#{omission}"
  end
end
