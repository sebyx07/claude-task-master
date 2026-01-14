# frozen_string_literal: true

require 'open3'
require 'json'

module ClaudeTaskMaster
  # GitHub operations via gh CLI
  # Handles PR creation, CI status, comments, and merging
  class GitHub
    # Check if gh CLI is available and authenticated
    def self.available?
      _, status = Open3.capture2('gh auth status')
      status.success?
    end

    # Get current repository (owner/repo format)
    def self.current_repo
      stdout, status = Open3.capture2('gh repo view --json nameWithOwner -q .nameWithOwner')
      return nil unless status.success?

      stdout.strip
    end

    # Create a PR
    # Returns [success, pr_number_or_error]
    def self.create_pr(title:, body:, base: 'main')
      cmd = [
        'gh', 'pr', 'create',
        '--title', title,
        '--body', body,
        '--base', base
      ]

      stdout, stderr, status = Open3.capture3(*cmd)

      if status.success?
        # Extract PR number from URL
        pr_url = stdout.strip
        pr_number = pr_url.split('/').last.to_i
        [true, pr_number]
      else
        [false, stderr.strip]
      end
    end

    # Get PR status (CI checks)
    # Returns hash with :status (:pending, :passing, :failing) and :checks array
    def self.pr_status(pr_number)
      cmd = ['gh', 'pr', 'checks', pr_number.to_s, '--json', 'name,state,bucket']
      stdout, status = Open3.capture2(*cmd)

      return { status: :unknown, checks: [] } unless status.success?

      checks = JSON.parse(stdout, symbolize_names: true)

      overall = if checks.any? { |c| c[:bucket] == 'fail' }
                  :failing
                elsif checks.any? { |c| c[:bucket] == 'pending' }
                  :pending
                else
                  :passing
                end

      { status: overall, checks: }
    end

    # Wait for CI to complete (blocking)
    # Returns final status
    def self.wait_for_ci(pr_number, timeout: 600)
      cmd = ['gh', 'pr', 'checks', pr_number.to_s, '--watch', '--fail-fast']

      Timeout.timeout(timeout) do
        _, status = Open3.capture2(*cmd)
        status.success? ? :passing : :failing
      end
    rescue Timeout::Error
      :timeout
    end

    # Get PR comments (all review comments)
    def self.pr_comments(pr_number)
      repo = current_repo
      return [] unless repo

      cmd = ['gh', 'api', '--paginate', "repos/#{repo}/pulls/#{pr_number}/comments"]
      stdout, status = Open3.capture2(*cmd)

      return [] unless status.success?

      JSON.parse(stdout, symbolize_names: true)
    end

    # Get unresolved review threads via GraphQL
    def self.unresolved_threads(pr_number)
      repo = current_repo
      return [] unless repo

      owner, name = repo.split('/')

      query = <<~GRAPHQL
        query {
          repository(owner: "#{owner}", name: "#{name}") {
            pullRequest(number: #{pr_number}) {
              reviewThreads(first: 100) {
                nodes {
                  id
                  isResolved
                  comments(first: 10) {
                    nodes {
                      body
                      author { login }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      stdout, status = Open3.capture2('gh', 'api', 'graphql', '-f', "query=#{query}")
      return [] unless status.success?

      response = JSON.parse(stdout, symbolize_names: true)
      threads = response.dig(:data, :repository, :pullRequest, :reviewThreads, :nodes) || []

      threads.reject { |t| t[:isResolved] }
    end

    # Merge PR
    def self.merge_pr(pr_number, method: 'squash')
      cmd = ['gh', 'pr', 'merge', pr_number.to_s, "--#{method}", '--delete-branch']
      _, status = Open3.capture2(*cmd)
      status.success?
    end

    # Get PR info
    def self.pr_info(pr_number)
      cmd = ['gh', 'pr', 'view', pr_number.to_s, '--json', 'number,title,state,url,headRefName']
      stdout, status = Open3.capture2(*cmd)

      return nil unless status.success?

      JSON.parse(stdout, symbolize_names: true)
    end
  end
end
