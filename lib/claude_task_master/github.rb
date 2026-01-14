# frozen_string_literal: true

require 'open3'
require 'json'
require 'octokit'

module ClaudeTaskMaster
  # GitHub operations via gh CLI and Octokit
  # Handles PR creation, CI status, comments, and merging
  class GitHub
    class << self
      # Check if gh CLI is available and authenticated
      def available?
        _, status = Open3.capture2('gh auth status')
        status.success?
      end

      # Get Octokit client using gh token
      def client
        @client ||= begin
          token = gh_token
          raise ConfigError, 'GitHub token not found. Run: gh auth login' unless token

          Octokit::Client.new(access_token: token, auto_paginate: true)
        end
      end

      # Reset client (useful for testing)
      def reset_client!
        @client = nil
      end

      # Get current repository (owner/repo format)
      def current_repo
        @current_repo ||= begin
          stdout, status = Open3.capture2('gh repo view --json nameWithOwner -q .nameWithOwner')
          return nil unless status.success?

          stdout.strip
        end
      end

      # Create a PR
      # Returns [success, pr_number_or_error]
      def create_pr(title:, body:, base: 'main', head: nil)
        head ||= current_branch
        repo = current_repo
        return [false, 'Not in a git repository'] unless repo

        pr = client.create_pull_request(repo, base, head, title, body)
        [true, pr.number]
      rescue Octokit::Error => e
        [false, e.message]
      end

      # Get PR status (CI checks)
      # Returns hash with :status (:pending, :passing, :failing) and :checks array
      def pr_status(pr_number)
        repo = current_repo
        return { status: :unknown, checks: [] } unless repo

        # Get check runs for the PR's head SHA
        pr = client.pull_request(repo, pr_number)
        checks = client.check_runs_for_ref(repo, pr.head.sha)

        check_results = checks.check_runs.map do |run|
          {
            name: run.name,
            status: run.status,
            conclusion: run.conclusion
          }
        end

        overall = determine_ci_status(check_results)
        { status: overall, checks: check_results }
      rescue Octokit::Error
        # Fallback to gh CLI
        gh_pr_status(pr_number)
      end

      # Get all PR review comments
      def pr_comments(pr_number)
        repo = current_repo
        return [] unless repo

        comments = client.pull_request_comments(repo, pr_number)
        PRComment.from_api_response(comments.map(&:to_h))
      rescue Octokit::Error => e
        warn "Failed to fetch comments: #{e.message}"
        []
      end

      # Get unresolved review threads via GraphQL
      def unresolved_threads(pr_number)
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
                        path
                        line
                      }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL

        response = client.post('/graphql', { query: query }.to_json)
        threads = response.dig(:data, :repository, :pullRequest, :reviewThreads, :nodes) || []

        threads.reject { |t| t[:isResolved] }.map do |thread|
          first_comment = thread.dig(:comments, :nodes)&.first
          {
            id: thread[:id],
            author: first_comment&.dig(:author, :login),
            body: first_comment&.dig(:body),
            file_path: first_comment&.dig(:path),
            line: first_comment&.dig(:line)
          }
        end
      rescue Octokit::Error, StandardError => e
        # Fallback to gh CLI
        gh_unresolved_threads(pr_number)
      end

      # Get actionable comments (unresolved + actionable severity)
      def actionable_comments(pr_number)
        comments = pr_comments(pr_number)
        unresolved_ids = unresolved_threads(pr_number).map { |t| t[:id] }

        comments.select do |comment|
          comment.actionable? || unresolved_ids.include?(comment.id)
        end
      end

      # Resolve a review thread
      def resolve_thread(thread_id)
        mutation = <<~GRAPHQL
          mutation {
            resolveReviewThread(input: {threadId: "#{thread_id}"}) {
              thread {
                id
                isResolved
              }
            }
          }
        GRAPHQL

        response = client.post('/graphql', { query: mutation }.to_json)
        errors = response[:errors]

        return true unless errors

        raise GitHubError, errors.map { |e| e[:message] }.join(', ')
      end

      # Reply to a PR comment
      def reply_to_comment(pr_number, comment_id, body)
        repo = current_repo
        return false unless repo

        client.create_pull_request_comment_reply(repo, pr_number, body, comment_id)
        true
      rescue Octokit::Error => e
        warn "Failed to reply: #{e.message}"
        false
      end

      # Wait for CI to complete (blocking)
      def wait_for_ci(pr_number, timeout: 600)
        cmd = ['gh', 'pr', 'checks', pr_number.to_s, '--watch', '--fail-fast']

        Timeout.timeout(timeout) do
          _, status = Open3.capture2(*cmd)
          status.success? ? :passing : :failing
        end
      rescue Timeout::Error
        :timeout
      end

      # Merge PR
      def merge_pr(pr_number, method: :squash, delete_branch: true)
        repo = current_repo
        return false unless repo

        client.merge_pull_request(repo, pr_number, '', merge_method: method)
        client.delete_branch(repo, pr_branch_name(pr_number)) if delete_branch
        true
      rescue Octokit::Error => e
        warn "Failed to merge: #{e.message}"
        false
      end

      # Get PR info
      def pr_info(pr_number)
        repo = current_repo
        return nil unless repo

        pr = client.pull_request(repo, pr_number)
        {
          number: pr.number,
          title: pr.title,
          state: pr.state,
          url: pr.html_url,
          head_ref: pr.head.ref,
          base_ref: pr.base.ref,
          mergeable: pr.mergeable,
          merged: pr.merged
        }
      rescue Octokit::Error
        nil
      end

      # List open PRs
      def open_prs
        repo = current_repo
        return [] unless repo

        client.pull_requests(repo, state: 'open').map do |pr|
          {
            number: pr.number,
            title: pr.title,
            head_ref: pr.head.ref
          }
        end
      rescue Octokit::Error
        []
      end

      private

      # Get GitHub token from gh CLI
      def gh_token
        stdout, status = Open3.capture2('gh auth token')
        return nil unless status.success?

        stdout.strip
      end

      # Get current git branch
      def current_branch
        stdout, status = Open3.capture2('git rev-parse --abbrev-ref HEAD')
        return nil unless status.success?

        stdout.strip
      end

      # Get PR branch name
      def pr_branch_name(pr_number)
        pr = client.pull_request(current_repo, pr_number)
        pr.head.ref
      rescue Octokit::Error
        nil
      end

      # Determine overall CI status from check results
      def determine_ci_status(checks)
        return :unknown if checks.empty?

        if checks.any? { |c| c[:conclusion] == 'failure' }
          :failing
        elsif checks.any? { |c| c[:status] != 'completed' }
          :pending
        else
          :passing
        end
      end

      # Fallback: Get PR status via gh CLI
      def gh_pr_status(pr_number)
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

        { status: overall, checks: checks }
      end

      # Fallback: Get unresolved threads via gh CLI
      def gh_unresolved_threads(pr_number)
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
    end
  end

  # Custom error class
  class GitHubError < StandardError; end
end
